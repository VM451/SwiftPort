package __BUNDLE_ID__

import __BUNDLE_ID__.data.ContractFixtures
import __BUNDLE_ID__.ui.TaskScreen
import app.cash.paparazzi.Paparazzi
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/// Paparazzi screenshot tests — every contract fixture × light/dark,
/// mirroring the Apple snapshot matrix. `swiftport verify --mode snapshots
/// --platforms android` runs these and pixel-diffs against
/// Verification/Snapshots/android goldens.
@RunWith(RobolectricTestRunner::class)
class TaskScreenSnapshotTest {

    @get:Rule
    val paparazzi = Paparazzi()

    private fun state(fileName: String) =
        ContractFixtures.fromAssets(RuntimeEnvironment.getApplication().assets, fileName)

    private fun snap(fileName: String, dark: Boolean) {
        paparazzi.snapshot {
            TaskScreen(state = state(fileName), darkTheme = dark)
        }
    }

    @Test fun loading__light() = snap("loading.json", dark = false)
    @Test fun loading__dark() = snap("loading.json", dark = true)
    @Test fun empty__light() = snap("empty.json", dark = false)
    @Test fun empty__dark() = snap("empty.json", dark = true)
    @Test fun populated__light() = snap("populated.json", dark = false)
    @Test fun populated__dark() = snap("populated.json", dark = true)
    @Test fun longText__light() = snap("longText.json", dark = false)
    @Test fun longText__dark() = snap("longText.json", dark = true)
    @Test fun error__light() = snap("error.json", dark = false)
    @Test fun error__dark() = snap("error.json", dark = true)
}
