package com.grindscale.android.ui

import android.app.Application
import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.FileProvider
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.grindscale.android.analysis.GrindAnalyzer
import com.grindscale.android.analysis.NormalizedRoi
import com.grindscale.android.analysis.withExifOrientation
import com.grindscale.android.domain.AnalysisHistoryRecord
import com.grindscale.android.domain.AnalysisMode
import com.grindscale.android.domain.AnalysisStats
import com.grindscale.android.domain.BrewProfile
import com.grindscale.android.domain.CoinReference
import com.grindscale.android.domain.CoinReferences
import com.grindscale.android.domain.HistogramBin
import com.grindscale.android.domain.Profiles
import com.grindscale.android.domain.RoastLevel
import com.grindscale.android.services.HistoryStore
import com.grindscale.android.services.RecommendationService
import com.grindscale.android.services.ReportExportService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

class AppViewModel(app: Application) : AndroidViewModel(app) {

    var selectedProfile by mutableStateOf(Profiles.all.first())
        private set
    var selectedCoin by mutableStateOf(CoinReferences.all.first())
        private set

    var beanDescription by mutableStateOf("")
    var roastLevel by mutableStateOf(RoastLevel.medium)
    var grinderDescription by mutableStateOf("")

    var analysisProgress by mutableDoubleStateOf(0.0)
    var selectedImage by mutableStateOf<Bitmap?>(null)
    var selectedImageUri by mutableStateOf<Uri?>(null)
    var coinRoiNormalized by mutableStateOf<NormalizedRoi?>(null)
    var overlayImage by mutableStateOf<Bitmap?>(null)
    var stats by mutableStateOf<AnalysisStats?>(null)
    var recommendation by mutableStateOf("")
    var qualityText by mutableStateOf("尚未分析")
    var calibrationText by mutableStateOf("相對模式（未校正）")
    var histogram by mutableStateOf<List<HistogramBin>>(emptyList())
    var histogramMetaText by mutableStateOf("")
    var chartRevision by mutableStateOf(0)
    var particleDiameters by mutableStateOf<List<Double>>(emptyList())
    var particleDiameterUnit by mutableStateOf("px")
    var coinCandidates by mutableStateOf<List<com.grindscale.android.domain.CoinCandidateDebug>>(emptyList())
    var history by mutableStateOf<List<AnalysisHistoryRecord>>(emptyList())
        private set
    var isAnalyzing by mutableStateOf(false)
    var errorMessage by mutableStateOf<String?>(null)
    var exportErrorMessage by mutableStateOf<String?>(null)
    var saveResultMessage by mutableStateOf<String?>(null)

    var shareLauncherTick by mutableIntStateOf(0)
        private set
    var pendingShareUri by mutableStateOf<Uri?>(null)
        private set
    var pendingShareMime by mutableStateOf("text/csv")

    private val analysisTargetSeconds = 240L
    private var progressJob: Job? = null

    private val historyStore = HistoryStore(app)

    init {
        refreshHistory()
    }

    fun refreshHistory() {
        history = historyStore.load()
    }

    fun clearExportError() {
        exportErrorMessage = null
    }

    fun clearSaveMessage() {
        saveResultMessage = null
    }

    /** Call from UI after handing off to share sheet intent. */
    fun clearPendingShare() {
        pendingShareUri = null
    }

    fun selectProfile(p: BrewProfile) {
        selectedProfile = p
    }

    fun selectCoin(c: CoinReference) {
        selectedCoin = c
    }

    fun onImagePicked(uri: Uri) {
        selectedImageUri = uri
        errorMessage = null
        try {
            val ctx = getApplication<Application>()
            ctx.contentResolver.openInputStream(uri)?.use { ins ->
                val bmp = BitmapFactory.decodeStream(ins)?.copy(Bitmap.Config.ARGB_8888, true)
                if (bmp == null) {
                    errorMessage = "無法載入圖片。"
                    return
                }
                val oriented =
                    ctx.contentResolver.openInputStream(uri)?.use { exifStream ->
                        bmp.withExifOrientation { exifStream }
                    } ?: bmp
                selectedImage = oriented
            }
        } catch (_: Exception) {
            errorMessage = "讀取相片失敗。"
        }
    }

    fun clearRoi() {
        coinRoiNormalized = null
    }

    /**
     * Returns a URI to pass to [androidx.activity.result.contract.ActivityResultContracts.TakePicture].
     * Caller should grant CAMERA permission before launching.
     */
    fun prepareCameraCaptureUri(): Uri {
        val app = getApplication<Application>()
        val target = File(app.cacheDir, "camera_capture.jpg")
        if (!target.exists()) {
            target.createNewFile()
        } else {
            target.delete()
            target.createNewFile()
        }
        return FileProvider.getUriForFile(app, "${app.packageName}.fileprovider", target)
    }

    fun analyzeImage() {
        val normalizedBmp = selectedImage ?: run {
            errorMessage = "請先選擇或拍攝照片。"
            return
        }
        val profile = selectedProfile
        val coin = selectedCoin
        val roi = coinRoiNormalized
        errorMessage = null
        isAnalyzing = true
        analysisProgress = 0.02
        startAnalysisProgressTimer()

        viewModelScope.launch {
            try {
                withContext(Dispatchers.Default) {
                    val analyzer = GrindAnalyzer
                    val result = analyzer.analyze(
                        normalizedBmp,
                        profile,
                        coin.diameterMM,
                        roi
                    )

                    if (coin.diameterMM != null && result.stats.mode != AnalysisMode.calibrated) {
                        withContext(Dispatchers.Main) {
                            progressJob?.cancel()
                            analysisProgress = 0.0
                            errorMessage =
                                "未偵測到硬幣，無法輸出 0-1000um 分布。請將硬幣完整放在白紙上並重拍。"
                            stats = null
                            overlayImage = null
                            recommendation = ""
                            calibrationText = "校正失敗"
                            histogram = emptyList()
                            histogramMetaText = ""
                            particleDiameters = emptyList()
                            particleDiameterUnit = "px"
                            coinCandidates = result.coinCandidates
                            isAnalyzing = false
                        }
                        return@withContext
                    }

                    val overlay = analyzer.overlayBitmap(
                        base = normalizedBmp,
                        particles = result.particles,
                        analyzedWidth = result.analyzedWidth,
                        analyzedHeight = result.analyzedHeight,
                        coinMarker = result.coinMarker,
                        coinCandidateOverlays = result.coinCandidateOverlays
                    )

                    val rec = RecommendationService.text(result.stats, profile.name)
                    val hist = buildHistogram(result.diameters, result.stats.mode)
                    val qualityProbe = analyzer.checkQuality(normalizedBmp)

                    withContext(Dispatchers.Main) {
                        analysisProgress = 1.0
                        progressJob?.cancel()
                        overlayImage = overlay
                        stats = result.stats
                        recommendation = rec
                        calibrationText = result.calibrationText
                        histogram = hist.bins
                        histogramMetaText = hist.meta
                        chartRevision += 1
                        particleDiameters = result.diameters.sorted()
                        particleDiameterUnit = result.stats.unitLabel
                        coinCandidates = result.coinCandidates
                        qualityText = String.format(
                            "亮度 %.1f / 對比 %.1f / 覆蓋率 %.3f %s",
                            qualityProbe.brightness,
                            qualityProbe.contrast,
                            qualityProbe.occupancy,
                            if (qualityProbe.pass) "（品質通過）" else "（建議重拍）"
                        )
                        val record =
                            AnalysisHistoryRecord(
                                id = UUID.randomUUID(),
                                timestampMillis = System.currentTimeMillis(),
                                profileName = profile.name,
                                mode = result.stats.mode,
                                score = result.stats.uniformityScore,
                                particleCount = result.stats.particleCount,
                                cv = result.stats.cv
                            )
                        historyStore.save(record)
                        refreshHistory()
                        delay(500)
                        isAnalyzing = false
                        analysisProgress = 0.0
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    progressJob?.cancel()
                    analysisProgress = 0.0
                    errorMessage = "分析失敗：${e.message}"
                    isAnalyzing = false
                }
            }
        }
    }

    private fun startAnalysisProgressTimer() {
        progressJob?.cancel()
        progressJob =
            viewModelScope.launch(Dispatchers.Default) {
                val start = System.currentTimeMillis()
                while (isActive && isAnalyzing) {
                    delay(250)
                    val elapsed = (System.currentTimeMillis() - start) / 1000.0
                    val linear = elapsed / analysisTargetSeconds
                    val prog =
                        if (linear <= 0.92) {
                            min(0.92, max(0.02, linear))
                        } else {
                            val overrun = elapsed - analysisTargetSeconds * 0.92
                            min(0.99, 0.92 + min(0.07, overrun / 2000))
                        }
                    withContext(Dispatchers.Main) {
                        if (isAnalyzing) analysisProgress = prog
                    }
                }
            }
    }

    fun exportCsvReport() {
        val s = stats
        if (s == null) {
            exportErrorMessage = "請先完成分析再匯出。"
            return
        }
        try {
            val bytes =
                ReportExportService.makeCsv(
                    stats = s,
                    profileName = selectedProfile.name,
                    coinName = selectedCoin.name,
                    calibrationText = calibrationText,
                    recommendation = recommendation,
                    histogram = histogram,
                    histogramMetaText = histogramMetaText,
                    particleDiameters = particleDiameters,
                    particleDiameterUnit = particleDiameterUnit,
                    reportDate = Date()
                )
            val uri = writeExportFile(tempExportBasename(".csv"), bytes)
            pendingShareMime = "text/csv"
            pendingShareUri = uri
            shareLauncherTick++
        } catch (e: Exception) {
            exportErrorMessage = "匯出失敗：${e.message}"
        }
    }

    fun exportPdfReport() {
        val s = stats
        if (s == null) {
            exportErrorMessage = "請先完成分析再匯出。"
            return
        }
        try {
            val bytes =
                ReportExportService.makePdf(
                    stats = s,
                    profileName = selectedProfile.name,
                    coinName = selectedCoin.name,
                    calibrationText = calibrationText,
                    recommendation = recommendation,
                    histogram = histogram,
                    histogramMetaText = histogramMetaText,
                    particleDiameters = particleDiameters,
                    particleDiameterUnit = particleDiameterUnit,
                    reportDate = Date(),
                    overlayImage = overlayImage
                )
            val uri = writeExportFile(tempExportBasename(".pdf"), bytes)
            pendingShareMime = "application/pdf"
            pendingShareUri = uri
            shareLauncherTick++
        } catch (e: Exception) {
            exportErrorMessage = "匯出失敗：${e.message}"
        }
    }

    fun saveOverlayImage() {
        val bmp = overlayImage
        if (bmp == null) {
            saveResultMessage = "沒有可下載的辨識結果圖片。"
            return
        }
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val uri = saveBitmapToGallery(bmp)
                withContext(Dispatchers.Main) {
                    saveResultMessage =
                        if (uri != null) {
                            "已儲存辨識圖片到相簿。"
                        } else {
                            "儲存失敗：無法建立相簿項目。"
                        }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    saveResultMessage = "儲存失敗：${e.message}"
                }
            }
        }
    }

    private fun tempExportBasename(suffix: String): String {
        val df =
            SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).apply {
                timeZone = java.util.TimeZone.getDefault()
            }
        return "GrindScale_粒徑報告_${df.format(Date())}$suffix"
    }

    private fun writeExportFile(name: String, bytes: ByteArray): Uri {
        val app = getApplication<Application>()
        val dir = File(app.cacheDir, "exports").apply { mkdirs() }
        val f = File(dir, name)
        f.writeBytes(bytes)
        return FileProvider.getUriForFile(app, "${app.packageName}.fileprovider", f)
    }

    private fun saveBitmapToGallery(bitmap: Bitmap): Uri? {
        val app = getApplication<Application>()
        val name = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()).let {
            "GrindScale_overlay_$it.jpg"
        }
        val values =
            ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/GrindScale")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
            }
        val resolver = app.contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return null
        val ok =
            resolver.openOutputStream(uri).use { out ->
                if (out == null) false else {
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 92, out)
                }
            }
        if (!ok) {
            resolver.delete(uri, null, null)
            return null
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val done = ContentValues().apply {
                put(MediaStore.Images.Media.IS_PENDING, 0)
            }
            resolver.update(uri, done, null, null)
        }
        return uri
    }

    private data class HistogramResult(val bins: List<HistogramBin>, val meta: String)

    private fun buildHistogram(diameters: List<Double>, mode: AnalysisMode): HistogramResult {
        if (mode != AnalysisMode.calibrated) {
            return HistogramResult(emptyList(), "需要硬幣校正後才顯示 0-1000um 曲線")
        }
        val minValue = 0.0
        val maxValue = 1000.0
        val binsCount = 40
        val step = (maxValue - minValue) / binsCount.toDouble()
        val buckets = IntArray(binsCount)
        var underflow = 0
        var overflow = 0
        for (d in diameters) {
            when {
                d < minValue -> underflow++
                d > maxValue -> overflow++
                else -> {
                    val idx = min(binsCount - 1, max(0, ((d - minValue) / step).toInt()))
                    buckets[idx]++
                }
            }
        }
        val bins = (0 until binsCount).map { i ->
            val start = minValue + i * step
            val end = start + step
            HistogramBin(start = start, end = end, count = buckets[i])
        }
        val minD = diameters.minOrNull() ?: 0.0
        val maxD = diameters.maxOrNull() ?: 0.0
        val meta =
            String.format(
                "顆粒總數 %d | 範圍外: <0um %d, >1000um %d | 本次最小/最大: %.1f / %.1f um",
                diameters.size,
                underflow,
                overflow,
                minD,
                maxD
            )
        return HistogramResult(bins, meta)
    }
}
