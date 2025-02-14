import 'package:auto_size_text/auto_size_text.dart';
import 'package:breez/bloc/account/account_actions.dart';
import 'package:breez/bloc/account/account_bloc.dart';
import 'package:breez/bloc/account/account_model.dart';
import 'package:breez/bloc/blocs_provider.dart';
import 'package:breez/logger.dart';
import 'package:breez/utils/exceptions.dart';
import 'package:breez/utils/min_font_size.dart';
import 'package:breez/widgets/back_button.dart' as backBtn;
import 'package:breez/widgets/error_dialog.dart';
import 'package:breez/widgets/fee_chooser.dart';
import 'package:breez/widgets/loader.dart';
import 'package:breez/widgets/single_button_bottom_bar.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SweepAllCoinsConfirmation extends StatefulWidget {
  final AccountBloc accountBloc;
  final String address;
  final Function() onPrevious;
  final Future Function(TxDetail tx) onConfirm;

  const SweepAllCoinsConfirmation({
    Key key,
    this.onPrevious,
    this.onConfirm,
    this.accountBloc,
    this.address,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return SweepAllCoinsConfirmationState();
  }
}

class SweepAllCoinsConfirmationState extends State<SweepAllCoinsConfirmation> {
  List<FeeOption> feeOptions;
  List<TxDetail> transactions;
  int selectedFeeIndex = 1;
  Future _txsDetailsFuture;
  Int64 _sweepAmount;
  bool _showConfirm = false;

  @override
  void initState() {
    super.initState();

    var action = SweepAllCoinsTxsAction(widget.address);
    widget.accountBloc.userActionsSink.add(action);
    _txsDetailsFuture = action.future.then((r) {
      SweepAllCoinsTxs response = r as SweepAllCoinsTxs;
      _sweepAmount = response.amount;
      List<int> targetConfirmations = response.transactions.keys.toList()
        ..sort();
      var trimmedTargetConfirmations = targetConfirmations.reversed.toList();
      if (trimmedTargetConfirmations.length > 3) {
        var middle = (targetConfirmations.length / 2).floor();
        trimmedTargetConfirmations = [
          targetConfirmations.last,
          targetConfirmations[middle],
          targetConfirmations.first
        ];
      }

      transactions = trimmedTargetConfirmations
          .map((index) => response.transactions[index])
          .toList();

      feeOptions =
          List.generate(trimmedTargetConfirmations.length, (index) => index)
              .map((index) => FeeOption(transactions[index].fees.toInt(),
                  trimmedTargetConfirmations[index]))
              .toList();
      if (feeOptions.length > 0) {
        setState(() {
          _showConfirm = true;
        });
      }
      selectedFeeIndex = (feeOptions.length / 2).floor();
      while (feeOptions.length < 3) {
        feeOptions.add(null);
        transactions.add(null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    final texts = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        iconTheme: themeData.appBarTheme.iconTheme,
        textTheme: themeData.appBarTheme.textTheme,
        backgroundColor: themeData.canvasColor,
        leading: backBtn.BackButton(onPressed: () {
          widget.onPrevious();
        }),
        title: Text(
          texts.sweep_all_coins_speed,
          style: themeData.appBarTheme.textTheme.headline6,
        ),
        elevation: 0.0,
      ),
      body: StreamBuilder<AccountModel>(
        stream: AppBlocsProvider.of<AccountBloc>(context).accountStream,
        builder: (context, snapshot) {
          AccountModel acc = snapshot.data;
          return FutureBuilder(
            future: _txsDetailsFuture,
            builder: (context, futureSnapshot) {
              if (futureSnapshot.error != null) {
                //render error
                return _ErrorMessage(
                  message: texts.sweep_all_coins_error_retrieve_fees,
                );
              }
              if (futureSnapshot.connectionState != ConnectionState.done ||
                  acc == null) {
                //render loader
                return SizedBox();
              }

              if (feeOptions.where((f) => f != null).length == 0) {
                return _ErrorMessage(
                  message: texts.sweep_all_coins_error_amount_small,
                );
              }

              return Container(
                height: 500.0,
                padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 40.0),
                width: MediaQuery.of(context).size.width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      child: FeeChooser(
                        economyFee: feeOptions[0],
                        regularFee: feeOptions[1],
                        priorityFee: feeOptions[2],
                        selectedIndex: this.selectedFeeIndex,
                        onSelect: (index) => setState(() {
                          this.selectedFeeIndex = index;
                        }),
                      ),
                    ),
                    SizedBox(height: 36.0),
                    buildSummary(context, acc),
                  ],
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: !_showConfirm
          ? null
          : SingleButtonBottomBar(
              text: texts.sweep_all_coins_action_confirm,
              onPressed: () {
                log.info("Sweep all coins using $selectedFeeIndex of ${transactions.logDescription((e) => e.fees.toString())}");
                Navigator.of(context).push(createLoaderRoute(context));
                widget.onConfirm(transactions[selectedFeeIndex]).then((_) {
                  Navigator.of(context).pop();
                }).catchError((error) {
                  log.warning("Sweep all coins error", error);
                  Navigator.of(context).pop();
                  promptError(
                    context,
                    null,
                    Text(
                      extractExceptionMessage(error, texts: texts),
                      style: themeData.dialogTheme.contentTextStyle,
                    ),
                  );
                });
              },
            ),
    );
  }

  Widget buildSummary(BuildContext context, AccountModel acc) {
    final themeData = Theme.of(context);
    final texts = AppLocalizations.of(context);
    final receive = _sweepAmount - feeOptions[selectedFeeIndex].sats;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(5.0)),
        border: Border.all(
          color: themeData.colorScheme.onSurface.withOpacity(0.4),
        ),
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Container(
              child: AutoSizeText(
                texts.sweep_all_coins_label_send,
                style: TextStyle(
                  color: Colors.white,
                ),
                maxLines: 1,
                minFontSize: MinFontSize(context).minFontSize,
                stepGranularity: 0.1,
              ),
            ),
            trailing: Container(
              child: AutoSizeText(
                acc.currency.format(_sweepAmount),
                style: TextStyle(
                  color: themeData.errorColor,
                ),
                maxLines: 1,
                minFontSize: MinFontSize(context).minFontSize,
                stepGranularity: 0.1,
              ),
            ),
          ),
          ListTile(
            title: Container(
              child: AutoSizeText(
                texts.sweep_all_coins_label_transaction_fee,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                ),
                maxLines: 1,
                minFontSize: MinFontSize(context).minFontSize,
                stepGranularity: 0.1,
              ),
            ),
            trailing: Container(
              child: AutoSizeText(
                texts.sweep_all_coins_fee(
                  acc.currency.format(
                    Int64(feeOptions[selectedFeeIndex].sats),
                  ),
                ),
                style: TextStyle(
                  color: themeData.errorColor.withOpacity(0.4),
                ),
                maxLines: 1,
                minFontSize: MinFontSize(context).minFontSize,
                stepGranularity: 0.1,
              ),
            ),
          ),
          ListTile(
            title: Container(
              child: AutoSizeText(
                texts.sweep_all_coins_label_receive,
                style: TextStyle(
                  color: Colors.white,
                ),
                maxLines: 1,
                minFontSize: MinFontSize(context).minFontSize,
                stepGranularity: 0.1,
              ),
            ),
            trailing: Container(
              child: AutoSizeText(
                acc.fiatCurrency == null
                    ? texts.sweep_all_coins_amount_no_fiat(
                        acc.currency.format(receive),
                      )
                    : texts.sweep_all_coins_amount_with_fiat(
                        acc.currency.format(receive),
                        acc.fiatCurrency.format(receive),
                      ),
                style: TextStyle(
                  color: themeData.errorColor,
                ),
                maxLines: 1,
                minFontSize: MinFontSize(context).minFontSize,
                stepGranularity: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  final String message;

  const _ErrorMessage({
    Key key,
    this.message,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40.0, left: 40.0, right: 40.0),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              message,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
