import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ume_core/ume_core.dart';

import 'api_client.dart';
import 'server_config_store.dart';

class AiVibePanel implements Pluggable {
  @override
  Widget? buildWidget(BuildContext? context) => const AiVibeFloatingPanel();

  @override
  String get displayName => 'AI Vibe Panel';

  @override
  ImageProvider<Object> get iconImageProvider =>
      MemoryImage(Uint8List.fromList(_iconPng));

  @override
  String get name => 'ai_vibe_panel';

  @override
  void onTrigger() {}
}

class AiVibeFloatingPanel extends StatelessWidget {
  const AiVibeFloatingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final panelWidth = size.width < 560 ? size.width - 24 : 420.0;
    final panelHeight = size.height < 720 ? size.height - 112 : 620.0;

    return Positioned(
      right: 12,
      top: 72,
      width: panelWidth,
      height: panelHeight,
      child: Material(
        color: Colors.white,
        elevation: 12,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: const AiVibePanelPage(),
      ),
    );
  }
}

class AiVibePanelPage extends StatefulWidget {
  const AiVibePanelPage({super.key});

  @override
  State<AiVibePanelPage> createState() => _AiVibePanelPageState();
}

class _AiVibePanelPageState extends State<AiVibePanelPage> {
  final _configStore = ServerConfigStore();
  final _apiClient = AiVibeApiClient();
  final _serverController = TextEditingController();
  final _instructionController = TextEditingController(
    text: '把按钮改成绿色，并把文案改成 Start',
  );

  String _status = 'idle';
  String _responseText = 'No response yet.';

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
  }

  @override
  void dispose() {
    _serverController.dispose();
    _instructionController.dispose();
    super.dispose();
  }

  Future<void> _loadServerUrl() async {
    final value = await _configStore.loadServerUrl();
    if (!mounted) {
      return;
    }
    setState(() => _serverController.text = value);
  }

  Future<void> _saveServerUrl() async {
    await _configStore.saveServerUrl(_serverController.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _status = 'idle';
      _responseText = 'Saved server URL: ${_serverController.text.trim()}';
    });
  }

  Future<void> _useDefaultServerUrl() async {
    _serverController.text = ServerConfigStore.defaultServerUrl;
    await _saveServerUrl();
  }

  Future<void> _sendInstruction() async {
    final instruction = _instructionController.text.trim();
    if (instruction.isEmpty) {
      setState(() {
        _status = 'error';
        _responseText = 'Instruction is empty.';
      });
      return;
    }

    setState(() {
      _status = 'sending';
      _responseText = 'Sending command...';
    });

    try {
      await _configStore.saveServerUrl(_serverController.text);
      final result = await _apiClient.sendCommand(
        serverUrl: _serverController.text,
        instruction: instruction,
      );
      const encoder = JsonEncoder.withIndent('  ');
      setState(() {
        _status = result.success ? 'success' : 'error';
        _responseText = encoder.convert({
          'status': _status,
          'message': result.message,
          'applied': result.applied,
          'reloadTriggered': result.reloadTriggered,
          'agentOutput': result.raw['agentOutput'],
          'changedFiles': result.raw['changedFiles'],
          'reloadMessage': result.raw['reloadMessage'],
        });
      });
    } catch (error) {
      setState(() {
        _status = 'error';
        _responseText = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF111827),
              border: Border(bottom: BorderSide(color: Colors.black12)),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Text(
                    'AI Vibe Panel',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: UMEWidget.closeActivatedPlugin,
                  icon: Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  Text('Status: $_status'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _serverController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Server URL',
                      hintText: ServerConfigStore.defaultServerUrl,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _saveServerUrl,
                          child: const Text('Save Server URL'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _useDefaultServerUrl,
                          child: const Text('Use Mac Default'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _instructionController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Instruction',
                      hintText: 'Describe the change you want.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _status == 'sending' ? null : _sendInstruction,
                    child: const Text('Send'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Response',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black12),
                      borderRadius: BorderRadius.circular(8),
                      color: const Color(0xFFF7F7F7),
                    ),
                    child: SelectableText(_responseText),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// A tiny 1x1 PNG keeps the plugin self-contained for the MVP.
const List<int> _iconPng = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
