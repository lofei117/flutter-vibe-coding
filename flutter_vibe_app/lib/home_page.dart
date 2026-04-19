import 'package:flutter/material.dart';

// The mock agent edits only these values for the first runnable demo.
const String homeTitle = 'Flutter Vibe Coding';
const String homeButtonLabel = 'Start22';
const Color homeButtonColor = Colors.green;
const String homeDescription =
    'Open UME and use AI Vibe Panel to modify this app.';

// Stable widget keys used as source-registry anchors. Do not rename without
// updating `lib/source_registry.dart`.
const Key homeTitleKey = ValueKey('home.title');
const Key homeDescriptionKey = ValueKey('home.description');
const Key helloButtonKey = ValueKey('home.helloButton');

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(homeTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                homeTitle,
                key: homeTitleKey,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              const Text(
                homeDescription,
                key: homeDescriptionKey,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: helloButtonKey,
                style: FilledButton.styleFrom(backgroundColor: homeButtonColor),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TodoListPage(),
                    ),
                  );
                },
                child: const Text(homeButtonLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TodoListPage extends StatefulWidget {
  const TodoListPage({super.key});

  @override
  State<TodoListPage> createState() => _TodoListPageState();
}

final List<_Todo> _appTodos = <_Todo>[];

class _TodoListPageState extends State<TodoListPage> {
  void _addTodo() {
    _showTodoDialog();
  }

  void _editTodo(_Todo todo) {
    _showTodoDialog(todo: todo);
  }

  void _deleteTodo(_Todo todo) {
    setState(() {
      _appTodos.remove(todo);
    });
  }

  Future<void> _showTodoDialog({_Todo? todo}) async {
    final controller = TextEditingController(text: todo?.title ?? '');

    final title = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(todo == null ? 'Add todo' : 'Edit todo'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Title'),
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    final trimmedTitle = title?.trim();
    if (!mounted || trimmedTitle == null || trimmedTitle.isEmpty) {
      return;
    }

    setState(() {
      if (todo == null) {
        _appTodos.add(_Todo(trimmedTitle));
      } else {
        todo.title = trimmedTitle;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Todo List')),
      body: _appTodos.isEmpty
          ? const Center(child: Text('No todos yet.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _appTodos.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final todo = _appTodos[index];

                return ListTile(
                  title: Text(todo.title),
                  leading: Checkbox(
                    value: todo.done,
                    onChanged: (value) {
                      setState(() {
                        todo.done = value ?? false;
                      });
                    },
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit),
                        onPressed: () => _editTodo(todo),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deleteTodo(todo),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTodo,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _Todo {
  _Todo(this.title);

  String title;
  bool done = false;
}
