package __BUNDLE_ID__.data

import android.content.res.AssetManager
import org.json.JSONObject

/// UI state phases — mirrors `TaskPhase` in Core/ and the `phase` field of
/// every Verification/Contracts/*.json fixture. Keep the wire values
/// identical across platforms; that is the contract.
enum class TaskPhase { LOADING, EMPTY, LOADED, ERROR }

data class TaskItem(
    val id: String,
    val title: String,
    val notes: String,
    val isCompleted: Boolean,
    val priority: String,
)

/// The deterministic state a platform UI must render for one contract
/// fixture. Produced by parsing the shared JSON — the same files the
/// Swift core tests and snapshot runner consume.
data class ContractState(
    val id: String,
    val phase: TaskPhase,
    val tasks: List<TaskItem>,
    val errorMessage: String?,
)

object ContractFixtures {
    fun fromAssets(assets: AssetManager, fileName: String): ContractState {
        val text = assets.open(fileName).bufferedReader().use { it.readText() }
        return parse(JSONObject(text))
    }

    fun parse(json: JSONObject): ContractState {
        val phase = when (json.getString("phase")) {
            "loading" -> TaskPhase.LOADING
            "empty" -> TaskPhase.EMPTY
            "loaded" -> TaskPhase.LOADED
            else -> TaskPhase.ERROR
        }
        val tasks = json.optJSONArray("tasks")?.let { array ->
            (0 until array.length()).map { i ->
                val t = array.getJSONObject(i)
                TaskItem(
                    id = t.getString("id"),
                    title = t.getString("title"),
                    notes = t.optString("notes"),
                    isCompleted = t.optBoolean("isCompleted"),
                    priority = t.optString("priority"),
                )
            }
        } ?: emptyList()
        val errorMessage = if (json.isNull("errorMessage")) null else json.optString("errorMessage")
        return ContractState(
            id = json.getString("id"),
            phase = phase,
            tasks = tasks,
            errorMessage = errorMessage,
        )
    }
}
