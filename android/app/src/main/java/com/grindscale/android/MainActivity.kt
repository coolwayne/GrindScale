package com.grindscale.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.viewmodel.compose.viewModel
import com.grindscale.android.ui.AppViewModel
import com.grindscale.android.ui.GrindscaleRoot
import com.grindscale.android.ui.theme.GrindScaleTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            GrindScaleTheme {
                val vm: AppViewModel = viewModel()
                GrindscaleRoot(vm)
            }
        }
    }
}
