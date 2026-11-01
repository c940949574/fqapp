import 'dart:convert';
import 'dart:io';

/// GPT-SoVITS 本地音色克隆 TTS —— **私人引擎，仅本机使用**。
///
/// 走的是本机整合包的命令行脚本（零交互、输出 WAV），不依赖任何在线服务，
/// 也**不走** Sherpa-ONNX：GPT-SoVITS 是 PyTorch 栈（.pth 权重），与
/// Piper/Kokoro 的 .onnx 模型是两套推理路线。
///
/// 用法：[synthesize] 传入正文与输出路径，返回 WAV 文件路径，由调用方播放。
/// 音色来自参考音频（`refWav` + `refText`），支持跨语种克隆（如日语音色说中文）。
class GptSovitsTts {
  GptSovitsTts._();

  /// 配置文件（JSON）。存在则覆盖下方默认值，便于换音色而不用改代码。
  ///
  /// 位置：`%LOCALAPPDATA%\fqapp\gpt_sovits.json`（Windows）。缺省时用 [_defaults]。
  static File get configFile => File(
    '${Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path}'
    r'\fqapp\gpt_sovits.json',
  );

  static const Map<String, dynamic> _defaults = {
    'root': r'E:/AIMODEL/GPT-SoVITS-v2pro-20261006',
    'python': r'E:/AIMODEL/GPT-SoVITS-v2pro-20261006/runtime/python.exe',
    'script':
        r'C:/Users/94094/.workbuddy/skills/gpt-sovits-tts/scripts/gpt_sovits_tts.py',
    'refWav': '',
    'refText': '',
    'refLang': 'jp',
    'textLang': 'zh',
    'model': 'v5turbo',
  };

  static Map<String, dynamic> _config = Map<String, dynamic>.from(_defaults);

  /// 重新读配置文件（文件不存在则用默认值）。
  static Future<void> reload() async {
    _config = Map<String, dynamic>.from(_defaults);
    final f = configFile;
    if (await f.exists()) {
      try {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is Map) {
          _config.addAll(decoded.cast<String, dynamic>());
        }
      } on FormatException {
        // 配置坏了就退回默认，不要让朗读整个挂掉。
      }
    }
  }

  static String _s(String key) => (_config[key] ?? '').toString();

  /// 是否已配置参考音频（没配就用不了，调用方应给出提示）。
  static bool get configured => _s('refWav').isNotEmpty && _s('refText').isNotEmpty;

  /// 引擎在选择列表里的展示名。
  static const engineId = 'gpt_sovits';
  static const engineLabel = 'GPT-SoVITS 音色克隆';

  /// 合成一段正文为 WAV，返回输出文件路径。
  ///
  /// [text] 为待合成文本；[outWav] 为输出路径（必须可写）。
  /// 合成速度实测约 1.8× 实时（RTX 4070，5 秒音频约 9 秒），不适合边说边听，
  /// 适合「先合成后播放」的听书场景。
  static Future<String> synthesize({
    required String text,
    required String outWav,
    int? steps,
    double? cfg,
  }) async {
    if (_config.isEmpty) await reload();
    if (!configured) {
      throw StateError(
        'GPT-SoVITS 未配置参考音频：请在 ${configFile.path} 里填 refWav / refText',
      );
    }
    final args = <String>[
      _s('script'),
      '--ref-wav', _s('refWav'),
      '--ref-text', _s('refText'),
      '--text', text,
      '--ref-lang', _s('refLang'),
      '--text-lang', _s('textLang'),
      '--model', _s('model'),
      '--out', outWav,
      if (steps != null) ...['--steps', '$steps'],
      if (cfg != null) ...['--cfg', '$cfg'],
    ];
    final result = await Process.run(
      _s('python'),
      args,
      workingDirectory: _s('root'),
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'GPT-SoVITS 合成失败 (exit ${result.exitCode}): '
        '${result.stderr}'.trim(),
      );
    }
    if (!File(outWav).existsSync()) {
      throw StateError('GPT-SoVITS 未产出音频文件: $outWav');
    }
    return outWav;
  }
}
