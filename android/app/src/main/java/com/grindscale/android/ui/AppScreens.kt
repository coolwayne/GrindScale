package com.grindscale.android.ui

import android.Manifest
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenu
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.grindscale.android.R
import com.grindscale.android.domain.AnalysisHistoryRecord
import com.grindscale.android.domain.AnalysisMode
import com.grindscale.android.domain.AnalysisStats
import com.grindscale.android.domain.BrewProfile
import com.grindscale.android.domain.CoinCandidateDebug
import com.grindscale.android.domain.CoinReference
import com.grindscale.android.domain.CoinReferences
import com.grindscale.android.domain.Profiles
import com.grindscale.android.domain.RoastLevel
import com.grindscale.android.ui.theme.CoffeeColors
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

@Composable
fun GrindscaleRoot(vm: AppViewModel) {
    val navController = rememberNavController()
    NavHost(navController = navController, startDestination = "splash") {
        composable("splash") {
            SplashScreen(
                onDone = {
                    navController.navigate("home") {
                        popUpTo("splash") { inclusive = true }
                    }
                }
            )
        }
        composable("home") {
            HomeScreen(vm = vm, onContinue = { navController.navigate("analysis") })
        }
        composable("analysis") {
            AnalysisScreen(vm = vm, navController = navController)
        }
    }
}

@Composable
private fun SplashScreen(onDone: () -> Unit) {
    LaunchedEffect(Unit) {
        kotlinx.coroutines.delay(2500)
        onDone()
    }
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(horizontal = 24.dp)
        ) {
            Image(
                painter = painterResource(id = R.drawable.launch_splash_image),
                contentDescription = null,
                modifier = Modifier
                    .fillMaxWidth(0.82f)
                    .heightIn(max = 420.dp),
                contentScale = ContentScale.Fit
            )
            Spacer(Modifier.height(22.dp))
            Text(
                "GrindScale",
                fontSize = 34.sp,
                fontWeight = FontWeight.Bold,
                color = CoffeeColors.labelBlack
            )
        }
    }
}

@Composable
private fun HomeScreen(vm: AppViewModel, onContinue: () -> Unit) {
    val profiles = remember { Profiles.all }
    var moreExpanded by remember { mutableStateOf(false) }
    Scaffold(containerColor = CoffeeColors.background) { padding ->
        Column(
            Modifier
                .padding(padding)
                .padding(20.dp)
                .verticalScroll(rememberScrollState())
        ) {
            Text(
                "選擇沖煮方式",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = CoffeeColors.labelBlack
            )
            Spacer(Modifier.height(6.dp))
            Text(
                "依器具對應理想粒徑區間；可展開填寫豆種與設備。",
                style = MaterialTheme.typography.bodyMedium,
                color = CoffeeColors.muted
            )
            Spacer(Modifier.height(16.dp))
            profiles.chunked(2).forEach { rowProfiles ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    rowProfiles.forEach { p ->
                        ProfileCard(
                            profile = p,
                            selected = vm.selectedProfile.id == p.id,
                            onClick = { vm.selectProfile(p) },
                            modifier = Modifier.weight(1f)
                        )
                    }
                    if (rowProfiles.size == 1) {
                        Spacer(Modifier.weight(1f))
                    }
                }
                Spacer(Modifier.height(14.dp))
            }

            OutlinedCard(
                shape = RoundedCornerShape(14.dp),
                border = BorderStroke(1.dp, CoffeeColors.cardStroke),
                colors = CardDefaults.outlinedCardColors(containerColor = CoffeeColors.card)
            ) {
                Column(Modifier.fillMaxWidth()) {
                    Row(
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .clickable { moreExpanded = !moreExpanded }
                                .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text("🍃", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "更多選項（選填）",
                            fontWeight = FontWeight.Medium,
                            color = CoffeeColors.labelBlack
                        )
                    }
                    AnimatedVisibility(visible = moreExpanded) {
                        Column(
                            Modifier
                                .padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            OutlinedTextField(
                                value = vm.beanDescription,
                                onValueChange = { vm.beanDescription = it },
                                label = { Text("豆種 / 產區") },
                                placeholder = { Text("選填，例如：衣索比亞 耶加雪菲") },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = false
                            )
                            RoastLevelPicker(
                                selected = vm.roastLevel,
                                onSelect = { vm.roastLevel = it }
                            )
                            OutlinedTextField(
                                value = vm.grinderDescription,
                                onValueChange = { vm.grinderDescription = it },
                                label = { Text("磨豆機") },
                                placeholder = { Text("選填，例如：Baratza Encore") },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = false
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(20.dp))
            Button(
                onClick = onContinue,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = CoffeeColors.amber,
                    contentColor = CoffeeColors.labelBlack
                ),
                shape = RoundedCornerShape(14.dp)
            ) {
                Text("進入分析", fontWeight = FontWeight.SemiBold)
            }
            Spacer(Modifier.height(12.dp))
            TextButton(
                onClick = {
                    vm.selectProfile(Profiles.skipDefault)
                    onContinue()
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("SKIP", fontWeight = FontWeight.SemiBold, color = CoffeeColors.labelBlack)
            }
            Text(
                "SKIP 將以「手沖咖啡」為預設沖煮方式。",
                style = MaterialTheme.typography.bodySmall,
                color = CoffeeColors.muted,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RoastLevelPicker(selected: RoastLevel, onSelect: (RoastLevel) -> Unit) {
    val levels = RoastLevel.entries
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = !expanded },
        modifier = Modifier.fillMaxWidth()
    ) {
        OutlinedTextField(
            value = selected.label,
            onValueChange = {},
            readOnly = true,
            label = { Text("烘焙程度") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier =
                Modifier
                    .menuAnchor()
                    .fillMaxWidth()
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            levels.forEach { lvl ->
                DropdownMenuItem(
                    text = { Text(lvl.label) },
                    onClick = {
                        onSelect(lvl)
                        expanded = false
                    }
                )
            }
        }
    }
}

@Composable
private fun ProfileCard(
    profile: BrewProfile,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        onClick = onClick,
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = CoffeeColors.card),
        border = BorderStroke(if (selected) 2.5.dp else 1.dp, if (selected) CoffeeColors.accent else CoffeeColors.cardStroke),
        shape = RoundedCornerShape(16.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = if (selected) 8.dp else 4.dp)
    ) {
        Column(Modifier.padding(14.dp)) {
            Text(profile.name, fontWeight = FontWeight.Bold, color = CoffeeColors.labelBlack)
            Spacer(Modifier.height(8.dp))
            Text("理想粒徑", style = MaterialTheme.typography.labelSmall, color = CoffeeColors.muted)
            Text(
                profile.idealRangeDescription,
                fontWeight = FontWeight.Medium,
                color = CoffeeColors.labelBlack
            )
        }
    }
}

@Composable
private fun AnalysisScreen(vm: AppViewModel, navController: NavHostController) {
    val ctx = LocalContext.current
    val pickGallery = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) vm.onImagePicked(uri)
    }
    val shareLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {}

    LaunchedEffect(vm.shareLauncherTick) {
        val uri = vm.pendingShareUri ?: return@LaunchedEffect
        val mime = vm.pendingShareMime
        val send =
            Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                putExtra(Intent.EXTRA_SUBJECT, "GrindScale 報告")
            }
        shareLauncher.launch(Intent.createChooser(send, "分享報告"))
        vm.clearPendingShare()
    }

    var cameraCaptureUri by remember { mutableStateOf<android.net.Uri?>(null) }
    val takePicture = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { success ->
        val u = cameraCaptureUri
        if (success && u != null) vm.onImagePicked(u)
    }
    val requestCameraPermission =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            val u = cameraCaptureUri
            if (granted && u != null) takePicture.launch(u)
        }

    vm.exportErrorMessage?.let { err ->
        AlertDialog(
            onDismissRequest = { vm.clearExportError() },
            confirmButton = {
                TextButton(onClick = { vm.clearExportError() }) {
                    Text("好")
                }
            },
            title = { Text("匯出") },
            text = { Text(err) }
        )
    }

    vm.saveResultMessage?.let { msg ->
        AlertDialog(
            onDismissRequest = { vm.clearSaveMessage() },
            confirmButton = {
                TextButton(onClick = { vm.clearSaveMessage() }) {
                    Text("OK")
                }
            },
            title = { Text("下載結果") },
            text = { Text(msg) }
        )
    }

    var coinDebugExpanded by remember { mutableStateOf(false) }

    Box(Modifier.fillMaxSize()) {
        Scaffold(containerColor = CoffeeColors.background) { padding ->
            Column(
                Modifier
                    .padding(padding)
                    .padding(20.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedButton(
                        enabled = !vm.isAnalyzing,
                        onClick = { navController.popBackStack() }
                    ) {
                        Text("〈 首頁")
                    }
                    Text(
                        "分析",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = CoffeeColors.labelBlack
                    )
                    Spacer(Modifier.size(72.dp))
                }

                SessionSummary(vm)
                Spacer(Modifier.height(14.dp))

                Text(
                    "拍攝建議：只拍白紙區域，將咖啡粉與硬幣都放在同一張白紙上，避免陽光直射。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = CoffeeColors.muted
                )
                Spacer(Modifier.height(14.dp))

                CoinPickerCard(vm)
                Spacer(Modifier.height(12.dp))

                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button(
                        onClick = {
                            cameraCaptureUri = vm.prepareCameraCaptureUri()
                            val u = cameraCaptureUri!!
                            val permitted =
                                ContextCompat.checkSelfPermission(ctx, Manifest.permission.CAMERA) ==
                                    android.content.pm.PackageManager.PERMISSION_GRANTED
                            if (permitted) takePicture.launch(u)
                            else requestCameraPermission.launch(Manifest.permission.CAMERA)
                        },
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = CoffeeColors.amber,
                            contentColor = CoffeeColors.labelBlack
                        ),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Text("拍照")
                    }
                    Button(
                        onClick = { pickGallery.launch("image/*") },
                        modifier = Modifier.weight(1f),
                        colors =
                            ButtonDefaults.buttonColors(
                                containerColor = CoffeeColors.card,
                                contentColor = CoffeeColors.labelBlack
                            ),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Text("相簿")
                    }
                }

                Spacer(Modifier.height(12.dp))
                vm.selectedImage?.let { bmp ->
                    RoiImageEditor(
                        bitmap = bmp,
                        roi = vm.coinRoiNormalized,
                        onRoiChange = { vm.coinRoiNormalized = it },
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .height(260.dp)
                                .clip(RoundedCornerShape(14.dp))
                                .background(CoffeeColors.card)
                    )
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(top = 6.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "手動硬幣 ROI：只在框內找硬幣",
                            style = MaterialTheme.typography.bodySmall,
                            color = CoffeeColors.muted
                        )
                        TextButton(onClick = { vm.clearRoi() }) {
                            Text("清除 ROI")
                        }
                    }
                } ?: Box(
                    Modifier
                        .fillMaxWidth()
                        .height(220.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(CoffeeColors.card),
                    contentAlignment = Alignment.Center
                ) {
                    Text("尚未選擇照片", color = CoffeeColors.muted)
                }

                Spacer(Modifier.height(12.dp))
                Button(
                    onClick = { vm.analyzeImage() },
                    enabled = !vm.isAnalyzing && vm.selectedImage != null,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = CoffeeColors.card,
                        contentColor = CoffeeColors.labelBlack
                    ),
                    shape = RoundedCornerShape(14.dp),
                    elevation = ButtonDefaults.buttonElevation(defaultElevation = 2.dp)
                ) {
                    Text("開始分析", fontWeight = FontWeight.Bold)
                }

                vm.errorMessage?.let {
                    Spacer(Modifier.height(8.dp))
                    Text(it, color = Color(0xFFB00020), style = MaterialTheme.typography.bodyMedium)
                }

                vm.stats?.let { s -> StatsResultBody(vm = vm, stats = s) }

                CoinDebugSection(
                    expanded = coinDebugExpanded,
                    onToggle = { coinDebugExpanded = !coinDebugExpanded },
                    candidates = vm.coinCandidates,
                    modifier = Modifier.padding(top = 14.dp)
                )

                Text(
                    vm.qualityText,
                    style = MaterialTheme.typography.bodySmall,
                    color = CoffeeColors.muted,
                    modifier = Modifier.padding(top = 8.dp)
                )

                HistorySection(history = vm.history)
                Spacer(Modifier.height(16.dp))
            }
        }

        AnimatedVisibility(
            visible = vm.isAnalyzing,
            modifier = Modifier.fillMaxSize(),
            enter = fadeIn(),
            exit = fadeOut()
        ) {
            AnalysisLoadingOverlayFullscreen(progress = vm.analysisProgress)
        }
    }
}

@Composable
private fun SessionSummary(vm: AppViewModel) {
    val bean = vm.beanDescription.trim().isNotBlank()
    val grinder = vm.grinderDescription.trim().isNotBlank()

    OutlinedCard(
        shape = RoundedCornerShape(12.dp),
        border = BorderStroke(1.dp, CoffeeColors.cardStroke),
        colors =
            CardDefaults.outlinedCardColors(
                containerColor = CoffeeColors.card.copy(alpha = 0.96f)
            )
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                "本次沖煮設定",
                fontWeight = FontWeight.SemiBold,
                style = MaterialTheme.typography.labelMedium,
                color = CoffeeColors.muted
            )
            Text(
                "${vm.selectedProfile.name} · ${vm.roastLevel.label}",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                color = CoffeeColors.labelBlack
            )
            if (bean) {
                Text("豆種：${vm.beanDescription}", style = MaterialTheme.typography.labelSmall, color = CoffeeColors.muted)
            }
            if (grinder) {
                Text("磨豆機：${vm.grinderDescription}", style = MaterialTheme.typography.labelSmall, color = CoffeeColors.muted)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CoinPickerCard(vm: AppViewModel) {
    val coins = remember { CoinReferences.all }
    var expanded by remember { mutableStateOf(false) }

    OutlinedCard(
        shape = RoundedCornerShape(14.dp),
        border = BorderStroke(1.dp, CoffeeColors.cardStroke),
        colors = CardDefaults.outlinedCardColors(containerColor = CoffeeColors.card)
    ) {
        Column(Modifier.padding(12.dp)) {
            Text(
                "沖煮：${vm.selectedProfile.name}",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = CoffeeColors.labelBlack
            )
            Spacer(Modifier.height(8.dp))
            Text("參照物", style = MaterialTheme.typography.bodySmall, color = CoffeeColors.muted)
            ExposedDropdownMenuBox(
                expanded = expanded,
                onExpandedChange = { expanded = !expanded },
                modifier = Modifier.fillMaxWidth()
            ) {
                OutlinedTextField(
                    value = vm.selectedCoin.name,
                    onValueChange = {},
                    readOnly = true,
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                    modifier =
                        Modifier
                            .menuAnchor()
                            .fillMaxWidth()
                )
                ExposedDropdownMenu(
                    expanded = expanded,
                    onDismissRequest = { expanded = false }
                ) {
                    coins.forEach { c: CoinReference ->
                        DropdownMenuItem(
                            text = { Text(c.name) },
                            onClick = {
                                vm.selectCoin(c)
                                expanded = false
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CoinDebugSection(
    expanded: Boolean,
    onToggle: () -> Unit,
    candidates: List<CoinCandidateDebug>,
    modifier: Modifier = Modifier
) {
    Column(modifier) {
        OutlinedCard(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            border = BorderStroke(1.dp, CoffeeColors.cardStroke)
        ) {
            Column {
                Row(
                    modifier =
                        Modifier
                            .fillMaxWidth()
                            .clickable(onClick = onToggle)
                            .padding(12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("硬幣偵測候選（除錯）", fontWeight = FontWeight.Medium)
                    Text(if (expanded) "收起" else "展開", style = MaterialTheme.typography.labelSmall)
                }
                AnimatedVisibility(
                    expanded,
                    modifier = Modifier.padding(start = 12.dp, end = 12.dp, bottom = 12.dp)
                ) {
                    CoinCandidateDebugSection(candidates)
                }
            }
        }
    }
}

@Composable
private fun StatsResultBody(vm: AppViewModel, stats: AnalysisStats) {
    Spacer(Modifier.height(14.dp))
    Text(
        "分析結果",
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.Bold,
        color = CoffeeColors.labelBlack
    )

    StatsMetricGrid(stats = stats)

    Text(
        vm.calibrationText,
        style = MaterialTheme.typography.bodySmall,
        color = CoffeeColors.muted,
        modifier = Modifier.padding(top = 6.dp)
    )
    Text(
        "建議：${vm.recommendation}",
        style = MaterialTheme.typography.bodyMedium,
        color = CoffeeColors.labelBlack,
        modifier = Modifier.padding(top = 10.dp)
    )

    when {
        vm.histogram.isNotEmpty() -> HistogramResultCard(vm)
        vm.histogramMetaText.isNotEmpty() ->
            Text(
                vm.histogramMetaText,
                style = MaterialTheme.typography.bodySmall,
                color = CoffeeColors.muted,
                modifier = Modifier.padding(top = 8.dp)
            )
    }

    if (vm.particleDiameters.isNotEmpty()) {
        ParticleDetailSection(vm.particleDiameters, vm.particleDiameterUnit)
    }

    vm.overlayImage?.let { ov ->
        Spacer(Modifier.height(12.dp))
        Text("辨識疊圖", fontWeight = FontWeight.SemiBold, color = CoffeeColors.labelBlack)
        Image(
            bitmap = ov.asImageBitmap(),
            contentDescription = null,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp)),
            contentScale = ContentScale.Fit
        )
        Button(
            onClick = { vm.saveOverlayImage() },
            modifier = Modifier
                .padding(top = 8.dp)
                .fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = CoffeeColors.amber.copy(alpha = 0.35f),
                contentColor = CoffeeColors.labelBlack
            ),
            shape = RoundedCornerShape(12.dp)
        ) {
            Text("下載辨識照片")
        }
        Text(
            "藍: 細粉 / 綠: 適合 / 紅: 粗粉",
            style = MaterialTheme.typography.bodySmall,
            color = CoffeeColors.muted,
            modifier = Modifier.padding(top = 4.dp)
        )
    }

    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(top = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        OutlinedButton(
            onClick = { vm.exportCsvReport() },
            modifier = Modifier.weight(1f),
            border = BorderStroke(1.dp, CoffeeColors.cardStroke),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = CoffeeColors.labelBlack)
        ) {
            Text("匯出 Excel (CSV)", maxLines = 2)
        }
        OutlinedButton(
            onClick = { vm.exportPdfReport() },
            modifier = Modifier.weight(1f),
            border = BorderStroke(1.dp, CoffeeColors.cardStroke),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = CoffeeColors.labelBlack)
        ) {
            Text("匯出 PDF 報告", maxLines = 2)
        }
    }
    Text(
        "Excel：UTF-8 CSV；PDF：粒徑分析報告。",
        style = MaterialTheme.typography.bodySmall,
        color = CoffeeColors.muted,
        modifier = Modifier.padding(top = 8.dp)
    )
}

@Composable
private fun HistogramResultCard(vm: AppViewModel) {
    Column(
        Modifier.padding(top = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            "粒徑分佈曲線（0–1000 µm）",
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.titleSmall,
            color = CoffeeColors.labelBlack
        )
        OutlinedCard(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            border = BorderStroke(1.dp, CoffeeColors.cardStroke),
            colors = CardDefaults.outlinedCardColors(containerColor = CoffeeColors.card)
        ) {
            Column(Modifier.padding(12.dp)) {
                key(vm.chartRevision) {
                    HistogramAreaChart(bins = vm.histogram)
                }
                if (vm.histogramMetaText.isNotBlank()) {
                    Text(
                        vm.histogramMetaText,
                        style = MaterialTheme.typography.bodySmall,
                        color = CoffeeColors.muted,
                        modifier = Modifier.padding(top = 6.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun ParticleDetailSection(diameters: List<Double>, unit: String) {
    Column(
        Modifier.padding(top = 12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text("顆粒尺寸明細", fontWeight = FontWeight.Bold, color = CoffeeColors.labelBlack)
        Text(
            "共辨識 ${diameters.size} 顆（等效直徑）",
            style = MaterialTheme.typography.bodySmall,
            color = CoffeeColors.muted
        )
        Column(
            Modifier
                .fillMaxWidth()
                .height(220.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(CoffeeColors.card)
                .padding(8.dp)
                .verticalScroll(rememberScrollState())
        ) {
            diameters.forEachIndexed { i, value ->
                Text(
                    String.format(Locale.US, "#%d  %.1f %s", i + 1, value, unit),
                    fontSize = MaterialTheme.typography.bodySmall.fontSize,
                    fontWeight = FontWeight.Normal,
                    fontFamily = FontFamily.Monospace,
                    color = CoffeeColors.labelBlack,
                    modifier = Modifier.padding(vertical = 2.dp)
                )
            }
        }
    }
}

@Composable
private fun StatsMetricGrid(stats: AnalysisStats) {
    val u = stats.unitLabel
    Column(Modifier.padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MetricCell(title = "Score", value = "${stats.uniformityScore}", modifier = Modifier.weight(1f))
            MetricCell(title = "顆粒數", value = "${stats.particleCount}", modifier = Modifier.weight(1f))
            MetricCell(title = "CV", value = String.format(Locale.US, "%.3f", stats.cv), modifier = Modifier.weight(1f))
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MetricCell(
                title = "細粉",
                value = String.format(Locale.US, "%.1f%%", stats.fineRatio * 100),
                modifier = Modifier.weight(1f)
            )
            MetricCell(
                title = "目標",
                value = String.format(Locale.US, "%.1f%%", stats.targetRatio * 100),
                modifier = Modifier.weight(1f)
            )
            MetricCell(
                title = "粗粉",
                value = String.format(Locale.US, "%.1f%%", stats.coarseRatio * 100),
                modifier = Modifier.weight(1f)
            )
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MetricCell(
                title = "D10",
                value = String.format(Locale.US, "%.0f %@", stats.d10, u),
                modifier = Modifier.weight(1f)
            )
            MetricCell(
                title = "D50",
                value = String.format(Locale.US, "%.0f %@", stats.d50, u),
                modifier = Modifier.weight(1f)
            )
            MetricCell(
                title = "D90",
                value = String.format(Locale.US, "%.0f %@", stats.d90, u),
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun MetricCell(title: String, value: String, modifier: Modifier = Modifier) {
    Column(
        modifier
            .clip(RoundedCornerShape(10.dp))
            .background(CoffeeColors.card)
            .border(
                BorderStroke(1.dp, CoffeeColors.cardStroke.copy(alpha = 0.5f)),
                RoundedCornerShape(10.dp)
            )
            .padding(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(value, fontWeight = FontWeight.Bold, color = CoffeeColors.labelBlack)
        Text(title, style = MaterialTheme.typography.labelSmall, color = CoffeeColors.muted)
    }
}

@Composable
private fun CoinCandidateDebugSection(candidates: List<CoinCandidateDebug>) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            "左側色塊與圖上圈圈同色；★ 為演算法自動選出；黃色為最終校正圈。",
            style = MaterialTheme.typography.bodySmall,
            color = CoffeeColors.muted
        )
        if (candidates.isEmpty()) {
            Text(
                "尚無候選資料，請先畫 ROI 再按「開始分析」。",
                style = MaterialTheme.typography.labelSmall,
                color = CoffeeColors.muted
            )
        } else {
            candidates.forEach { candidate ->
                val mark = if (candidate.selected) "★" else " "
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier =
                            Modifier
                                .size(14.dp)
                                .clip(CircleShape)
                                .background(CoinCandidatePalette.color(candidate.rank, candidate.selected))
                    )
                    Text(
                        String.format(
                            Locale.US,
                            "%s #%d  delta %.0f  面積 %.0f  直徑 %.1f px  分 %.2f",
                            mark,
                            candidate.rank,
                            candidate.circularity,
                            candidate.area,
                            candidate.support,
                            candidate.score
                        ),
                        style = MaterialTheme.typography.labelSmall,
                        color = CoffeeColors.labelBlack,
                        fontFamily = FontFamily.Monospace
                    )
                }
            }
        }
    }
}

@Composable
private fun HistorySection(history: List<AnalysisHistoryRecord>) {
    if (history.isEmpty()) return
    val timeFormatter =
        remember {
            DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.getDefault())
        }

    fun formatTimeMillis(millis: Long): String =
        Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).format(timeFormatter)

    Column(
        Modifier.padding(top = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text("最近分析紀錄", fontWeight = FontWeight.Bold, color = CoffeeColors.labelBlack)
        history.take(5).forEach { item ->
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    formatTimeMillis(item.timestampMillis),
                    style = MaterialTheme.typography.labelSmall,
                    color = CoffeeColors.muted
                )
                Text(item.profileName, style = MaterialTheme.typography.labelSmall, color = CoffeeColors.labelBlack)
                Text(
                    if (item.mode == AnalysisMode.calibrated) "校正" else "相對",
                    style = MaterialTheme.typography.labelSmall,
                    modifier =
                        Modifier
                            .border(1.dp, CoffeeColors.cardStroke, RoundedCornerShape(50))
                            .padding(horizontal = 6.dp, vertical = 2.dp),
                    color = CoffeeColors.labelBlack
                )
                Text("Score ${item.score}", style = MaterialTheme.typography.labelSmall)
                Text(String.format(Locale.US, "CV %.3f", item.cv), style = MaterialTheme.typography.labelSmall)
            }
        }
    }
}

@Composable
private fun AnalysisLoadingOverlayFullscreen(progress: Double) {
    val p = progress.coerceIn(0.0, 1.0)
    val phaseDetail =
        when {
            p <= 0.30 -> "正在辨識顆粒並計算粒徑分布"
            p <= 0.70 -> "正在分析數據"
            else -> "正在撰寫Excel跟專業報告"
        }
    Box(
        Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures { /* absorb touches while analyzing */ }
            }
            .background(Color.Black.copy(alpha = 0.4f)),
        contentAlignment = Alignment.Center
    ) {
        Card(
            shape = RoundedCornerShape(22.dp),
            elevation = CardDefaults.cardElevation(10.dp),
            colors = CardDefaults.cardColors(containerColor = Color.White),
            modifier =
                Modifier
                    .padding(24.dp)
                    .fillMaxWidth(0.92f)
        ) {
            Column(
                Modifier.padding(28.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(18.dp)
            ) {
                AnalysisLoopVideo(
                    modifier =
                        Modifier
                            .size(120.dp)
                            .clip(RoundedCornerShape(18.dp))
                            .background(Color.White)
                )

                Text(
                    "專業分析報告需要慢工出細活",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = CoffeeColors.labelBlack
                )
                Text(
                    phaseDetail,
                    style = MaterialTheme.typography.bodyMedium,
                    color = CoffeeColors.muted,
                    modifier = Modifier.fillMaxWidth()
                )
                Column(
                    Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    LinearProgressIndicator(
                        progress = { p.toFloat() },
                        modifier = Modifier.fillMaxWidth(),
                        trackColor = CoffeeColors.cardStroke,
                        color = CoffeeColors.labelBlack
                    )
                    Text(
                        "${(p * 100).toInt()}%",
                        style = MaterialTheme.typography.labelSmall,
                        color = CoffeeColors.labelBlack,
                        fontFamily = FontFamily.Monospace
                    )
                }
            }
        }
    }
}

@Composable
private fun AnalysisLoopVideo(modifier: Modifier) {
    val ctx = LocalContext.current
    val hasVideo =
        remember {
            try {
                ctx.resources.openRawResource(R.raw.analysis_loading_loop).close()
                true
            } catch (_: Exception) {
                false
            }
        }
    if (hasVideo) {
        AndroidView(
            factory = { c ->
                val player =
                    ExoPlayer.Builder(c).build().apply {
                        val uri =
                            android.net.Uri.parse(
                                "android.resource://${c.packageName}/${R.raw.analysis_loading_loop}"
                            )
                        setMediaItem(MediaItem.fromUri(uri))
                        repeatMode = Player.REPEAT_MODE_ONE
                        playWhenReady = true
                        prepare()
                    }
                PlayerView(c).apply {
                    useController = false
                    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                    this.player = player
                    tag = player
                    setBackgroundColor(android.graphics.Color.WHITE)
                }
            },
            modifier = modifier,
            onRelease = { view ->
                (view.tag as? ExoPlayer)?.release()
            }
        )
    } else {
        Box(modifier.background(CoffeeColors.card), contentAlignment = Alignment.Center) {
            Text("⋯", style = MaterialTheme.typography.headlineMedium)
        }
    }
}