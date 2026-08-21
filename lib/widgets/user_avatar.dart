import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/user_model.dart';
import '../theme/app_theme.dart';

/// The user's picture, falling back to an initials monogram.
///
/// Three states, in order of preference:
///  1. the uploaded avatar from the server,
///  2. a gradient monogram built from their name,
///  3. a person glyph if there is no name at all.
///
/// The fallback is not an error state — most users never upload a picture,
/// so the monogram has to look deliberate rather than broken.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    required this.user,
    this.size = 72,
    this.showBusy = false,
    super.key,
  });

  final UserModel? user;
  final double size;

  /// Dims the avatar and overlays a spinner while an upload is in flight.
  final bool showBusy;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final String? url = AppConfig.resolveMediaUrl(user?.avatarUrl);

    return SizedBox(
      height: size,
      width: size,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ClipOval(
            child: url == null
                ? _Monogram(user: user, size: size)
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    // Cache at roughly the rendered size rather than the
                    // uploaded resolution — a 1024px file scaled into a
                    // 72px circle otherwise wastes memory on every frame.
                    cacheWidth: (size * 3).round(),
                    loadingBuilder: (
                      BuildContext context,
                      Widget child,
                      ImageChunkEvent? progress,
                    ) {
                      if (progress == null) return child;
                      return Container(
                        color: palette.surfaceAlt,
                        alignment: Alignment.center,
                        child: SizedBox(
                          height: size * 0.3,
                          width: size * 0.3,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(palette.accent),
                          ),
                        ),
                      );
                    },
                    // A dead URL must not leave a broken-image glyph on the
                    // profile header — fall back to the monogram.
                    errorBuilder: (BuildContext context, Object _, StackTrace? __) =>
                        _Monogram(user: user, size: size),
                  ),
          ),
          if (showBusy)
            ClipOval(
              child: Container(
                color: Colors.black.withValues(alpha: 0.55),
                alignment: Alignment.center,
                child: SizedBox(
                  height: size * 0.32,
                  width: size * 0.32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.user, required this.size});

  final UserModel? user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final String initials = user?.initials ?? '';

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.voltGradient),
      alignment: Alignment.center,
      child: initials.isEmpty || initials == '?'
          ? Icon(
              Icons.person_rounded,
              size: size * 0.5,
              color: palette.onAccent,
            )
          : Text(
              initials,
              style: TextStyle(
                fontSize: size * 0.36,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: AppColors.onVolt,
              ),
            ),
    );
  }
}
