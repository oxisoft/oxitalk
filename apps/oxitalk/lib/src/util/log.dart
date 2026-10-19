/// The app's diagnostic log. Lines go nowhere until [logSink] is set, and the sink drops them
/// while the user hasn't turned logging on.
library;

enum LogLevel { error, warn, info, debug }

typedef LogSink = void Function(LogLevel level, String target, String message);

LogSink logSink = (_, _, _) {};

void appLog(LogLevel level, String target, String message) =>
    logSink(level, target, message);
