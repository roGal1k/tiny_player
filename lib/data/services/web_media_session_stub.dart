import '../../domain/models/track.dart';

class WebMediaSessionHelper {
  static void updateMetadata(Track track) {}
  static void setActionHandlers({
    void Function()? onPlay,
    void Function()? onPause,
    void Function()? onPrevious,
    void Function()? onNext,
    void Function(Duration)? onSeek,
  }) {}
}
