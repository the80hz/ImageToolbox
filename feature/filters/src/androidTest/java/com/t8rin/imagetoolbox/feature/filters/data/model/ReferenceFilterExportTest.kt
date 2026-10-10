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
 * Каждый из 10 фильтров применяется с параметрами по умолчанию, плюс `SimpleSolarizeFilter` и две
 * нестандартные матрицы (`*_custom`), к `reference/ui-sample.png` (64x64) через `transform`.
 * Результат пишется PNG в `getExternalFilesDir(null)/reference`.
 * Вход пишется туда же как `input.png` (байты совпадают с ассетом). Файлы забираются через adb pull.
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
