package __BUNDLE_ID__

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import __BUNDLE_ID__.bridge.SwiftPortBridge
import __BUNDLE_ID__.data.ContractFixtures
import __BUNDLE_ID__.data.ContractState
import __BUNDLE_ID__.data.TaskItem
import __BUNDLE_ID__.data.TaskPhase
import __BUNDLE_ID__.ui.TaskScreen
import org.json.JSONObject

/// Reference shell. Renders the shared "populated" contract state —
/// preferring the Swift Core bridge (`libswiftportcore.so` via JNI) when
/// the native library is present, falling back to the contract fixture
/// otherwise. `swiftport verify` contract tests exercise the same fixture.
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val fixtureJson = assets.open("populated.json").bufferedReader().use { it.readText() }
        val state = runCatching {
            SwiftPortBridge.snapshotFromFixture(fixtureJson)?.toContractState("populated")
        }.getOrNull() ?: ContractFixtures.parse(JSONObject(fixtureJson))
        setContent {
            TaskScreen(state = state)
        }
    }
}

private fun SwiftPortBridge.TaskListSnapshot.toContractState(id: String): ContractState =
    ContractState(
        id = id,
        phase = when (phase) {
            SwiftPortBridge.TaskPhase.LOADING -> TaskPhase.LOADING
            SwiftPortBridge.TaskPhase.EMPTY -> TaskPhase.EMPTY
            SwiftPortBridge.TaskPhase.LOADED -> TaskPhase.LOADED
            SwiftPortBridge.TaskPhase.ERROR -> TaskPhase.ERROR
        },
        tasks = tasks.map {
            TaskItem(it.id, it.title, it.notes, it.isCompleted, it.priority)
        },
        errorMessage = errorMessage,
    )
