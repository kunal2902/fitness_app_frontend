import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// The message input.
///
/// The send button is always enabled-looking but only fires with text —
/// a greyed-out button that suddenly lights up is more distracting than a
/// steady one, and the empty case is a no-op anyway.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    required this.onSend,
    required this.onChanged,
    this.enabled = true,
    this.hintText = 'Message…',
    super.key,
  });

  final void Function(String text) onSend;
  final void Function(String text) onChanged;
  final bool enabled;
  final String hintText;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    final bool next = value.trim().isNotEmpty;
    if (next != _hasText) setState(() => _hasText = next);
    widget.onChanged(value);
  }

  void _handleSend() {
    final String text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;

    widget.onSend(text);
    _controller.clear();
    setState(() => _hasText = false);

    // Keep focus so a conversation can be typed without re-tapping.
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: ConstrainedBox(
                // Grows with the message, but never eats the thread.
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  onChanged: _handleChanged,
                  onSubmitted: (_) => _handleSend(),
                  maxLines: null,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(4000),
                  ],
                  style: context.text.bodyMedium
                      ?.copyWith(color: palette.textPrimary),
                  cursorColor: palette.accent,
                  decoration: InputDecoration(
                    hintText: widget.enabled
                        ? widget.hintText
                        : 'Connecting…',
                    isDense: true,
                    filled: true,
                    fillColor: palette.surfaceAlt,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm + 2,
                    ),
                    border: const OutlineInputBorder(
                      borderRadius: AppRadius.rXl,
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppRadius.rXl,
                      borderSide: BorderSide(color: palette.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppRadius.rXl,
                      borderSide: BorderSide(color: palette.accent, width: 1.4),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _SendButton(
              enabled: widget.enabled && _hasText,
              onPressed: _handleSend,
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return AnimatedContainer(
      duration: AppDuration.fast,
      height: 44,
      width: 44,
      decoration: BoxDecoration(
        color: enabled ? palette.accent : palette.surfaceAlt,
        shape: BoxShape.circle,
        border: enabled ? null : Border.all(color: palette.border),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: Icon(
            Icons.arrow_upward_rounded,
            size: AppSize.iconMd,
            color: enabled ? palette.onAccent : palette.textTertiary,
          ),
        ),
      ),
    );
  }
}
