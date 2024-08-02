import 'package:flutter_mvvm_architecture/base.dart';

import '/shared/services/logging_service.dart';
import '/shared/services/indoor_positioning_service.dart';

//ToDo : Maybe change the name of the viewModel as we currently receive fused positions ( Tracelet Positions + Platform Specific Positions)
class TraceletManagerViewModel extends ViewModel {
  IndoorPositioningService get _indoorPositioningService =>
      getService<IndoorPositioningService>();

  LoggingService get _loggingService => getService<LoggingService>();

  bool get isConnected => _indoorPositioningService.isConnected;

  void startPositioning() => _indoorPositioningService.startPositioning();

  void stopPositioning() => _indoorPositioningService.stopPositioning();

  int get logMessageCount {
    // length is O(1) under the hood (ObservableBuffer)
    return _loggingService.buffer.length;
  }

  String logMessageByIndex(int index) {
    // elementAt() is O(1) under the hood (ObservableBuffer)
    return _loggingService.buffer.elementAt(index).toString();
  }

  @override
  void dispose() {
    _indoorPositioningService.onDispose();
    super.dispose();
  }
}
