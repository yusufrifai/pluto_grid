import 'dart:async';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:collection/collection.dart'; // untuk firstWhereOrNull

import '../ui.dart';

class PlutoColumnFilter extends PlutoStatefulWidget {
  final PlutoGridStateManager stateManager;

  final PlutoColumn column;

  PlutoColumnFilter({
    required this.stateManager,
    required this.column,
    Key? key,
  }) : super(key: ValueKey('column_filter_${column.key}'));

  @override
  PlutoColumnFilterState createState() => PlutoColumnFilterState();
}

class PlutoColumnFilterState extends PlutoStateWithChange<PlutoColumnFilter> {
  List<PlutoRow> _filterRows = [];

  String _text = '';

  bool _enabled = false;

  late final StreamSubscription _event;

  late final FocusNode _focusNode;

  late final TextEditingController _controller;

  String get _filterValue {
    return _filterRows.isEmpty
        ? ''
        : _filterRows.first.cells[FilterHelper.filterFieldValue]!.value
            .toString();
  }

  bool get _hasCompositeFilter {
    return _filterRows.length > 1 ||
        stateManager
            .filterRowsByField(FilterHelper.filterFieldAllColumns)
            .isNotEmpty;
  }

  InputBorder get _border => OutlineInputBorder(
        borderSide: BorderSide(
            color: stateManager.configuration.style.borderColor, width: 0.0),
        borderRadius: BorderRadius.zero,
      );

  InputBorder get _enabledBorder => OutlineInputBorder(
        borderSide: BorderSide(
            color: stateManager.configuration.style.activatedBorderColor,
            width: 0.0),
        borderRadius: BorderRadius.zero,
      );

  InputBorder get _disabledBorder => OutlineInputBorder(
        borderSide: BorderSide(
            color: stateManager.configuration.style.inactivatedBorderColor,
            width: 0.0),
        borderRadius: BorderRadius.zero,
      );

  Color get _textFieldColor => _enabled
      ? stateManager.configuration.style.cellColorInEditState
      : stateManager.configuration.style.cellColorInReadOnlyState;

  EdgeInsets get _padding =>
      widget.column.filterPadding ??
      stateManager.configuration.style.defaultColumnFilterPadding;

  @override
  PlutoGridStateManager get stateManager => widget.stateManager;

  String _getFormattedValue(PlutoColumn column, String raw) {
    if (column.field != FilterHelper.filterFieldValue) return raw;

    final filterRows = stateManager.filterRows;

    final currentFilterRow = filterRows.firstWhereOrNull(
          (row) => row.cells[FilterHelper.filterFieldValue]?.value == raw,
    );

    if (currentFilterRow == null) return raw;

    final columnField =
        currentFilterRow.cells[FilterHelper.filterFieldColumn]?.value;
    final targetColumn = stateManager.refColumns.firstWhereOrNull(
          (col) => col.field == columnField,
    );

    if (targetColumn?.type is PlutoColumnTypeNumber) {
      final number = int.tryParse(raw.replaceAll('.', '')) ?? 0;
      return NumberFormat.decimalPattern('id_ID').format(number);
    }

    return raw;
  }
  String _format(String raw) {
    if (raw.trim().isEmpty) return '';
    final number = int.tryParse(raw.replaceAll('.', ''));
    if (number == null) return '';
    return NumberFormat.decimalPattern('id_ID').format(number);
  }

  String _unformat(String formatted) {
    return formatted.replaceAll('.', '');
  }

  @override
  initState() {
    super.initState();

    _focusNode = FocusNode(onKeyEvent: _handleOnKey);

    widget.column.setFilterFocusNode(_focusNode);

    // _controller = TextEditingController(text: _filterValue);
    final rawValue = _filterValue ?? '';
    _controller = TextEditingController(
      text: _getFormattedValue(widget.column, rawValue),
    );
    _controller.addListener(() {
      final text = _controller.text;
      final isNumber = widget.column.type is PlutoColumnTypeNumber;
      if (isNumber) {
        final raw = _unformat(text);
        final formatted = _format(raw);

        // Cegah loop tak berujung
        if (_controller.text != formatted) {
          _controller.value = _controller.value.copyWith(
            text: formatted,
            selection: TextSelection.collapsed(offset: formatted.length),
          );

          // Simpan raw ke dalam stateManager
          final currentFilterRow = stateManager.filterRows.firstWhereOrNull(
                (row) => row.cells['column']?.value == widget.column.field,
          );

          if (currentFilterRow != null) {
            currentFilterRow.cells['value']?.value = raw;
            stateManager.notifyListeners();
          }
        }
      }
    });

    _event = stateManager.eventManager!.listener(_handleFocusFromRows);

    updateState(PlutoNotifierEventForceUpdate.instance);
  }

  @override
  dispose() {
    _event.cancel();

    _controller.dispose();

    _focusNode.dispose();

    super.dispose();
  }

  @override
  void updateState(PlutoNotifierEvent event) {
    _filterRows = update<List<PlutoRow>>(
      _filterRows,
      stateManager.filterRowsByField(widget.column.field),
      compare: listEquals,
    );

    if (_focusNode.hasPrimaryFocus != true) {
      _text = update<String>(_text, _filterValue);

      if (changed) {
        _controller.text = _text;
      }
    }

    _enabled = update<bool>(
      _enabled,
      widget.column.enableFilterMenuItem && !_hasCompositeFilter,
    );
  }

  void _moveDown({required bool focusToPreviousCell}) {
    if (!focusToPreviousCell || stateManager.currentCell == null) {
      stateManager.setCurrentCell(
        stateManager.refRows.first.cells[widget.column.field],
        0,
        notify: false,
      );

      stateManager.scrollByDirection(PlutoMoveDirection.down, 0);
    }

    stateManager.setKeepFocus(true, notify: false);

    stateManager.gridFocusNode.requestFocus();

    stateManager.notifyListeners();
  }

  KeyEventResult _handleOnKey(FocusNode node, KeyEvent event) {
    var keyManager = PlutoKeyManagerEvent(
      focusNode: node,
      event: event,
    );

    if (keyManager.isKeyUpEvent) {
      return KeyEventResult.handled;
    }

    final handleMoveDown =
        (keyManager.isDown || keyManager.isEnter || keyManager.isEsc) &&
            stateManager.refRows.isNotEmpty;

    final handleMoveHorizontal = keyManager.isTab ||
        (_controller.text.isEmpty && keyManager.isHorizontal);

    final skip = !(handleMoveDown || handleMoveHorizontal || keyManager.isF3);

    if (skip) {
      if (keyManager.isUp) {
        return KeyEventResult.handled;
      }

      return stateManager.keyManager!.eventResult.skip(
        KeyEventResult.ignored,
      );
    }

    if (handleMoveDown) {
      _moveDown(focusToPreviousCell: keyManager.isEsc);
    } else if (handleMoveHorizontal) {
      stateManager.nextFocusOfColumnFilter(
        widget.column,
        reversed: keyManager.isLeft || keyManager.isShiftPressed,
      );
    } else if (keyManager.isF3) {
      stateManager.showFilterPopup(
        _focusNode.context!,
        calledColumn: widget.column,
        onClosed: () {
          stateManager.setKeepFocus(true, notify: false);
          _focusNode.requestFocus();
        },
      );
    }

    return KeyEventResult.handled;
  }

  void _handleFocusFromRows(PlutoGridEvent plutoEvent) {
    if (!_enabled) {
      return;
    }

    if (plutoEvent is PlutoGridCannotMoveCurrentCellEvent &&
        plutoEvent.direction.isUp) {
      var isCurrentColumn = widget
              .stateManager
              .refColumns[stateManager.columnIndexesByShowFrozen[
                  plutoEvent.cellPosition.columnIdx!]]
              .key ==
          widget.column.key;

      if (isCurrentColumn) {
        stateManager.clearCurrentCell(notify: false);
        stateManager.setKeepFocus(false);
        _focusNode.requestFocus();
      }
    }
  }

  void _handleOnTap() {
    stateManager.setKeepFocus(false);
  }

  void _handleOnChanged(String changed) {
    stateManager.eventManager!.addEvent(
      PlutoGridChangeColumnFilterEvent(
        column: widget.column,
        filterType: widget.column.defaultFilter,
        filterValue: changed,
        debounceMilliseconds:
            stateManager.configuration.columnFilter.debounceMilliseconds,
      ),
    );
  }

  void _handleOnEditingComplete() {
    // empty for ignore event of OnEditingComplete.
  }

  bool get _isNumberColumn => widget.column.type is PlutoColumnTypeNumber;

  String _formatNumber(String raw) {
    if (raw.isEmpty) return '';
    final number = int.tryParse(raw.replaceAll('.', '')) ?? 0;
    return NumberFormat.decimalPattern('id_ID').format(number);
  }

  String _unformatNumber(String formatted) {
    return formatted.replaceAll('.', '');
  }

  @override
  Widget build(BuildContext context) {
    final style = stateManager.style;

    return SizedBox(
      height: stateManager.columnFilterHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: BorderDirectional(
            top: BorderSide(color: style.borderColor),
            end: style.enableColumnBorderVertical
                ? BorderSide(color: style.borderColor)
                : BorderSide.none,
          ),
        ),
        child: Padding(
          padding: _padding,
          child: Center(
            child: TextField(
              focusNode: _focusNode,
              controller: _controller,
              enabled: _enabled,
              style: style.cellTextStyle,
              keyboardType:
              _isNumberColumn ? TextInputType.number : TextInputType.text,
              onTap: _handleOnTap,
              // onChanged: _handleOnChanged,
              onChanged: (value) {
                if (_isNumberColumn) {
                  final raw = _unformatNumber(value);
                  final formatted = _format(raw);
                  // _controller.value = _controller.value.copyWith(
                  //   text: formatted,
                  //   selection: TextSelection.collapsed(offset: formatted.length),
                  // );
                  _handleOnChanged(raw);
                } else {
                  _handleOnChanged(value);
                }
              },
              onEditingComplete: _handleOnEditingComplete,
              decoration: InputDecoration(
                hintText: _enabled ? widget.column.defaultFilter.title : '',
                filled: true,
                fillColor: _textFieldColor,
                border: _border,
                enabledBorder: _border,
                disabledBorder: _disabledBorder,
                focusedBorder: _enabledBorder,
                contentPadding: const EdgeInsets.all(5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
