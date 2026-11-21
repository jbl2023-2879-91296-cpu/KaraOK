const authBurstLimit = 5;
const authBurstWindow = Duration(seconds: 30);
const authFirstLock = Duration(seconds: 30);
const authRepeatLock = Duration(seconds: 60);
const authStrikeReset = Duration(minutes: 15);
const authDefaultRetrySeconds = 60;

String countdownLabel(Duration duration) {
  final seconds = (duration.inMilliseconds / 1000).ceil().clamp(0, 86400);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
