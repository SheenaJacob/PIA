import 'package:flutter/material.dart' hide View;
import 'package:flutter_mvvm_architecture/base.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../view_models/tracelet_manager_view_model.dart';

class TraceletManagerView extends View<TraceletManagerViewModel> {
  const TraceletManagerView({super.key})
      : super(create: TraceletManagerViewModel.new);

  @override
  Widget build(BuildContext context, TraceletManagerViewModel viewModel) {
    final localizations = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(localizations.indoorPositioningDialogHeading),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: viewModel.logMessageCount,
              itemBuilder: (context, i) => Text(
                viewModel.logMessageByIndex(i),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          Flexible(
            child: Wrap(
              spacing: 5,
              children: [
                TextButton(
                  onPressed: !viewModel.isPositioning
                      ? viewModel.startPositioning
                      : null,
                  child: Text(localizations.indoorPositioningDialogConnectButton),
                ),
                TextButton(
                  onPressed: viewModel.isPositioning
                      ? viewModel.stopPositioning
                      : null,
                  child: Text(localizations.indoorPositioningDialogDisconnectButton),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
