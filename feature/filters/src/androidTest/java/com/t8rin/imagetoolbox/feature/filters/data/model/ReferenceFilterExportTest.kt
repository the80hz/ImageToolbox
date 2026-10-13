/*
 * ImageToolbox is an image editor for android
 * Copyright (c) 2026 T8RIN (Malik Mukhametzyanov)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * You should have received a copy of the Apache License
 * along with this program.  If not, see <http://www.apache.org/licenses/LICENSE-2.0>.
 */

package com.t8rin.imagetoolbox.feature.filters.data.model

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.t8rin.imagetoolbox.core.domain.model.IntegerSize
import com.t8rin.imagetoolbox.core.domain.transformation.Transformation
import com.t8rin.imagetoolbox.core.domain.utils.qto
import com.t8rin.imagetoolbox.core.filters.domain.model.enums.BlurEdgeMode
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Снимает эталоны для сверки iOS-порта фильтров (docs/ios-port/FILTERS.md, раздел 9).
 *
 * Каждый фильтр из списка применяется с параметрами по умолчанию (конструктор без аргументов или
 * значения по умолчанию из `ProceduralEffect`), плюс две нестандартные матрицы (`*_custom`),
 * к `reference/ui-sample.png` (64x64) через `transform`.
 * Результат пишется PNG в `getExternalFilesDir(null)/reference`.
 * Вход пишется туда же как `input.png` (байты совпадают с ассетом). Файлы забираются через adb pull.
 *
 * Не снимаются недетерминированные фильтры: `GrainFilter` и `RandomDitheringFilter` (два прогона дают
 * разные PNG). `LevelsFilter` по умолчанию тождественен, поэтому снят вариант `LevelsFilter_custom`.
 * `GaussianBlurFilter_r5` и `GaussianBlurFilter_r40` проверяют размеры ядра 11 и 81 (края libblur).
 *
 * Размер не меняется: `IntegerSize.Undefined` даёт `Size.ORIGINAL` в `GPUFilterTransformation`.
 */
@RunWith(AndroidJUnit4::class)
class ReferenceFilterExportTest {

    @Test
    fun exportDefaultFilterResults() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val outDir = File(instrumentation.targetContext.getExternalFilesDir(null), "reference")
        outDir.deleteRecursively()
        outDir.mkdirs()

        val inputBytes = instrumentation.context.assets.open(INPUT_ASSET).use { it.readBytes() }
        File(outDir, "input.png").writeBytes(inputBytes)

        val input = BitmapFactory.decodeByteArray(
            inputBytes,
            0,
            inputBytes.size,
            BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
        )
        assertNotNull("Не удалось декодировать $INPUT_ASSET", input)

        for ((name, filter) in filters()) {
            val result = runBlocking { filter.transform(input, IntegerSize.Undefined) }

            assertEquals("$name: ширина", input.width, result.width)
            assertEquals("$name: высота", input.height, result.height)
            assertFalse("$name: результат совпал со входом", result.sameAs(input))

            File(outDir, "$name.png").outputStream().use {
                result.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
            result.recycle()
        }
        input.recycle()
    }

    private fun filters(): List<Pair<String, Transformation<Bitmap>>> = listOf(
        "SepiaFilter" to SepiaFilter(),
        "NegativeFilter" to NegativeFilter(),
        "BlackAndWhiteFilter" to BlackAndWhiteFilter(),
        "SolarizeFilter" to SolarizeFilter(),
        "PosterizeFilter" to PosterizeFilter(),
        "GaussianBlurFilter" to GaussianBlurFilter(),
        "PixelationFilter" to PixelationFilter(),
        "VignetteFilter" to VignetteFilter(),
        "SharpenFilter" to SharpenFilter(),
        "SaturationFilter" to SaturationFilter(),
        "SimpleSolarizeFilter" to SimpleSolarizeFilter(),
        "ExposureFilter" to ExposureFilter(),
        "HueFilter" to HueFilter(),
        "WhiteBalanceFilter" to WhiteBalanceFilter(),
        "BulgeDistortionFilter" to BulgeDistortionFilter(),
        "SwirlDistortionFilter" to SwirlDistortionFilter(),
        "SphereRefractionFilter" to SphereRefractionFilter(),
        "GlassSphereRefractionFilter" to GlassSphereRefractionFilter(),
        "ZoomBlurFilter" to ZoomBlurFilter(),
        "GlassHexTilesFilter" to GlassHexTilesFilter(),
        "GlassRectTilesFilter" to GlassRectTilesFilter(),
        "GlassTriangleTilesFilter" to GlassTriangleTilesFilter(),
        "LogarithmicSpiralFilter" to LogarithmicSpiralFilter(),
        "SpiralDrosteFilter" to SpiralDrosteFilter(),
        "GradientMapFilter" to GradientMapFilter(),
        "BrightnessFilter" to BrightnessFilter(),
        "ContrastFilter" to ContrastFilter(),
        "GammaFilter" to GammaFilter(),
        "VibranceFilter" to VibranceFilter(),
        "HighlightsAndShadowsFilter" to HighlightsAndShadowsFilter(),
        "BoxBlurFilter" to BoxBlurFilter(),
        "MotionBlurFilter" to MotionBlurFilter(),
        "BokehFilter" to BokehFilter(),
        "LinearTiltShiftFilter" to LinearTiltShiftFilter(),
        "RadialTiltShiftFilter" to RadialTiltShiftFilter(),
        "FastBlurFilter" to FastBlurFilter(),
        "NativeStackBlurFilter" to NativeStackBlurFilter(),
        "MedianBlurFilter" to MedianBlurFilter(),
        "TentBlurFilter" to TentBlurFilter(),
        "BilaterialBlurFilter" to BilaterialBlurFilter(),
        "FastBilaterialBlurFilter" to FastBilaterialBlurFilter(),
        "UnsharpFilter" to UnsharpFilter(),
        "CirclePixelationFilter" to CirclePixelationFilter(),
        "DiamondPixelationFilter" to DiamondPixelationFilter(),
        "ProtanopiaFilter" to ProtanopiaFilter(),
        "DeuteranopiaFilter" to DeuteranopiaFilter(),
        "TritanopiaFilter" to TritanopiaFilter(),
        "AchromatopsiaFilter" to AchromatopsiaFilter(),
        "ProtonomalyFilter" to ProtonomalyFilter(),
        "DeutaromalyFilter" to DeutaromalyFilter(),
        "TritonomalyFilter" to TritonomalyFilter(),
        "AchromatomalyFilter" to AchromatomalyFilter(),
        "AmatorkaFilter" to AmatorkaFilter(),
        "KodakFilter" to KodakFilter(),
        "BleachBypassFilter" to BleachBypassFilter(),
        "CandlelightFilter" to CandlelightFilter(),
        "CelluloidFilter" to CelluloidFilter(),
        "CoffeeFilter" to CoffeeFilter(),
        "DropBluesFilter" to DropBluesFilter(),
        "EdgyAmberFilter" to EdgyAmberFilter(),
        "FallColorsFilter" to FallColorsFilter(),
        "FilmStock50Filter" to FilmStock50Filter(),
        "FoggyNightFilter" to FoggyNightFilter(),
        "GoldenForestFilter" to GoldenForestFilter(),
        "FloydSteinbergDitheringFilter" to FloydSteinbergDitheringFilter(),
        "FalseFloydSteinbergDitheringFilter" to FalseFloydSteinbergDitheringFilter(),
        "JarvisJudiceNinkeDitheringFilter" to JarvisJudiceNinkeDitheringFilter(),
        "SierraDitheringFilter" to SierraDitheringFilter(),
        "TwoRowSierraDitheringFilter" to TwoRowSierraDitheringFilter(),
        "SierraLiteDitheringFilter" to SierraLiteDitheringFilter(),
        "AtkinsonDitheringFilter" to AtkinsonDitheringFilter(),
        "StuckiDitheringFilter" to StuckiDitheringFilter(),
        "BurkesDitheringFilter" to BurkesDitheringFilter(),
        "LeftToRightDitheringFilter" to LeftToRightDitheringFilter(),
        "BayerTwoDitheringFilter" to BayerTwoDitheringFilter(),
        "BayerThreeDitheringFilter" to BayerThreeDitheringFilter(),
        "BayerFourDitheringFilter" to BayerFourDitheringFilter(),
        "BayerEightDitheringFilter" to BayerEightDitheringFilter(),
        "Clustered2x2DitheringFilter" to Clustered2x2DitheringFilter(),
        "Clustered4x4DitheringFilter" to Clustered4x4DitheringFilter(),
        "Clustered8x8DitheringFilter" to Clustered8x8DitheringFilter(),
        "SimpleThresholdDitheringFilter" to SimpleThresholdDitheringFilter(),
        "DilationFilter" to DilationFilter(),
        "ErodeFilter" to ErodeFilter(),
        "OpeningFilter" to OpeningFilter(),
        "ClosingFilter" to ClosingFilter(),
        "TopHatFilter" to TopHatFilter(),
        "BlackHatFilter" to BlackHatFilter(),
        "MorphologicalGradientFilter" to MorphologicalGradientFilter(),
        "AcesFilmicToneMappingFilter" to AcesFilmicToneMappingFilter(),
        "HableFilmicToneMappingFilter" to HableFilmicToneMappingFilter(),
        "HejlBurgessToneMappingFilter" to HejlBurgessToneMappingFilter(),
        "LogarithmicToneMappingFilter" to LogarithmicToneMappingFilter(),
        "UchimuraFilter" to UchimuraFilter(),
        "DragoFilter" to DragoFilter(),
        "EqualizeFilter" to EqualizeFilter(),
        "EqualizeHistogramFilter" to EqualizeHistogramFilter(),
        "EqualizeHistogramHSVFilter" to EqualizeHistogramHSVFilter(),
        "EqualizeHistogramPixelationFilter" to EqualizeHistogramPixelationFilter(),
        "ClaheFilter" to ClaheFilter(),
        "EqualizeHistogramAdaptiveFilter" to EqualizeHistogramAdaptiveFilter(),
        "FishEyeFilter" to FishEyeFilter(),
        "TwirlFilter" to TwirlFilter(),
        "PinchFilter" to PinchFilter(),
        "KaleidoscopeFilter" to KaleidoscopeFilter(),
        "RippleFilter" to RippleFilter(),
        "GlitchFilter" to GlitchFilter(),
        // Размер ядра 11 и 81 вместо 51: проверка краёв libblur (sigma 2 и 15).
        "GaussianBlurFilter_r5" to GaussianBlurFilter(Triple(5f, 2f, BlurEdgeMode.Reflect101)),
        "GaussianBlurFilter_r40" to GaussianBlurFilter(Triple(40f, 15f, BlurEdgeMode.Reflect101)),
        // По умолчанию Levels тождественен (0..1 в 0..1), поэтому берём нестандартные уровни.
        "LevelsFilter_custom" to LevelsFilter(0.1f to 0.9f qto (0.2f to 0.8f)),
        // Нестандартные матрицы: строки записаны подряд, по строке на выходной канал.
        "ColorMatrix3x3Filter_custom" to ColorMatrix3x3Filter(
            floatArrayOf(
                1.2f, -0.1f, 0.0f,
                0.1f, 0.9f, 0.05f,
                -0.2f, 0.3f, 1.1f,
            )
        ),
        "ColorMatrix4x4Filter_custom" to ColorMatrix4x4Filter(
            floatArrayOf(
                1.1f, 0.0f, 0.2f, 0.0f,
                -0.1f, 0.9f, 0.0f, 0.05f,
                0.0f, 0.1f, 0.8f, 0.0f,
                0.0f, 0.0f, 0.0f, 1.0f,
            )
        ),
    )

    private companion object {
        const val INPUT_ASSET = "reference/ui-sample.png"
    }
}
