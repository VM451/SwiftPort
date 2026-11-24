package __BUNDLE_ID__.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.List
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import __BUNDLE_ID__.data.ContractState
import __BUNDLE_ID__.data.TaskItem
import __BUNDLE_ID__.data.TaskPhase

/// Material Design 3 theme. `darkTheme = null` follows the system; the
/// snapshot tests pass an explicit value for deterministic goldens.
@Composable
fun SwiftPortTheme(
    darkTheme: Boolean? = null,
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme ?: isSystemInDarkTheme()) darkColorScheme() else lightColorScheme(),
        content = content,
    )
}

/// Root screen — renders every `TaskPhase` explicitly, mirroring
/// `TaskListView` on Apple. Loading, empty, loaded and error are all
/// designed states; an unhandled phase is a contract violation.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TaskScreen(
    state: ContractState,
    darkTheme: Boolean? = null,
    modifier: Modifier = Modifier,
) {
    SwiftPortTheme(darkTheme = darkTheme) {
        Surface(modifier = modifier.fillMaxSize()) {
            Scaffold(
                topBar = { TopAppBar(title = { Text("__APP_NAME__") }) },
            ) { padding ->
                Box(
                    modifier = Modifier.padding(padding).fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    when (state.phase) {
                        TaskPhase.LOADING -> LoadingState()
                        TaskPhase.EMPTY -> EmptyState()
                        TaskPhase.LOADED -> TaskList(state.tasks)
                        TaskPhase.ERROR -> ErrorState(state.errorMessage)
                    }
                }
            }
        }
    }
}

@Composable
private fun LoadingState() {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        CircularProgressIndicator()
        Spacer(Modifier.height(12.dp))
        Text("Loading tasks…", color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun EmptyState() {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(
            Icons.Filled.CheckCircle,
            contentDescription = null,
            modifier = Modifier.height(48.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.height(12.dp))
        Text("No Tasks", style = MaterialTheme.typography.titleLarge)
        Text(
            "Your shared task list will appear here.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun ErrorState(message: String?) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(
            Icons.Filled.Warning,
            contentDescription = null,
            modifier = Modifier.height(48.dp),
            tint = MaterialTheme.colorScheme.error,
        )
        Spacer(Modifier.height(12.dp))
        Text("Couldn't Load Tasks", style = MaterialTheme.typography.titleLarge)
        Text(
            message ?: "An unknown error occurred.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(12.dp))
        Button(onClick = { /* retry arrives with the Core bridge */ }) {
            Text("Try Again")
        }
    }
}

@Composable
private fun TaskList(tasks: List<TaskItem>) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(tasks, key = { it.id }) { task -> TaskRow(task) }
    }
}

@Composable
private fun TaskRow(task: TaskItem) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = if (task.isCompleted) Icons.Filled.CheckCircle else Icons.Filled.List,
                contentDescription = if (task.isCompleted) "Completed" else "Not completed",
                tint = if (task.isCompleted) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
            )
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    task.title,
                    style = MaterialTheme.typography.bodyLarge,
                    textDecoration = if (task.isCompleted) TextDecoration.LineThrough else null,
                    color = if (task.isCompleted) {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    },
                )
                if (task.notes.isNotEmpty()) {
                    Text(
                        task.notes,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Spacer(Modifier.width(8.dp))
            AssistChip(
                onClick = { /* actions arrive with the Core bridge */ },
                label = {
                    Text(task.priority.replaceFirstChar { it.uppercase() })
                },
            )
        }
    }
}
