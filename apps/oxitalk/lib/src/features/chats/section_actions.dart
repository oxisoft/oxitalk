import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import 'room_groups.dart';

/// What the user does with sections, for one account; failures show as a snack bar.
final class SectionActions {
  SectionActions(this._context, this._ref, this._account);

  final BuildContext _context;
  final WidgetRef _ref;
  final String _account;

  MatrixSession? get _session =>
      _ref.read(accountsProvider).value?.byId(_account);

  Sections get _sections =>
      _ref.read(sectionsProvider(_account)).value ?? const Sections();

  Future<void> _run(
    String what,
    Future<void> Function(MatrixSession) call,
  ) async {
    final session = _session;
    if (session == null) return;
    try {
      await call(session);
    } on MatrixFailure catch (failure) {
      if (_context.mounted) {
        ScaffoldMessenger.of(
          _context,
        ).showSnackBar(SnackBar(content: Text('$what: ${failure.kind.name}')));
      }
    }
  }

  /// Puts [room] in the section with [tag], or in its default one with `null`.
  Future<void> setSection(Room room, String? tag) => _run(
    'Can’t move the chat',
    (session) => session.setRoomSection(room.id, tag),
  );

  /// Asks for a name, makes the section just above Rooms, and moves [room] into it if given.
  Future<void> create({Room? room}) async {
    final name = await _askName(title: 'New section');
    if (name == null) return;
    final sections = _sections;
    final tag = newSectionTag();
    final order = movableOrder(sections);
    order.insert(order.indexOf(SectionTags.rooms), tag);
    await _run(
      'Can’t make the section',
      (session) => session.saveSections([
        ...sections.custom,
        CustomSection(tag, name),
      ], order),
    );
    if (room != null) await setSection(room, tag);
  }

  Future<void> rename(String tag) async {
    final sections = _sections;
    final current = sections.custom.where((s) => s.tag == tag).firstOrNull;
    if (current == null) return;
    final name = await _askName(title: 'Rename section', initial: current.name);
    if (name == null || name == current.name) return;
    await _run(
      'Can’t rename the section',
      (session) => session.saveSections([
        for (final section in sections.custom)
          section.tag == tag ? CustomSection(tag, name) : section,
      ], movableOrder(sections)),
    );
  }

  /// Moves the section one place up ([by] = -1) or down (1) among the movable ones.
  Future<void> move(String tag, int by) {
    final sections = _sections;
    return _run(
      'Can’t move the section',
      (session) => session.saveSections(
        sections.custom,
        moved(movableOrder(sections), tag, by),
      ),
    );
  }

  /// Deletes the section after asking; its chats go back to People or Rooms.
  Future<void> delete(String tag) async {
    final sections = _sections;
    final current = sections.custom.where((s) => s.tag == tag).firstOrNull;
    if (current == null) return;
    final sure = await showDialog<bool>(
      context: _context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${current.name}”?'),
        content: const Text(
          'Its chats go back to People or Rooms. Nothing else is deleted.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('section.delete'),
            style: OxiButtons.destructiveFilled(context),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await _run(
      'Can’t delete the section',
      (session) => session.saveSections(
        [
          for (final section in sections.custom)
            if (section.tag != tag) section,
        ],
        [
          for (final other in movableOrder(sections))
            if (other != tag) other,
        ],
      ),
    );
  }

  /// Lets the user pick the section for [room], or make a new one.
  Future<void> chooseFor(Room room) async {
    final sections = _sections;
    final current = sectionOf(room, sections);
    const newSection = '\u0000new';
    const none = '\u0000none';
    final choice = await showDialog<String>(
      context: _context,
      builder: (context) => SimpleDialog(
        title: const Text('Move to section'),
        children: [
          for (final (tag, title) in [
            (SectionTags.favourites, sectionTitle(SectionTags.favourites)),
            for (final section in sections.custom) (section.tag, section.name),
            (SectionTags.lowPriority, sectionTitle(SectionTags.lowPriority)),
            (none, room.isDm ? 'People' : 'Rooms'),
          ])
            SimpleDialogOption(
              key: Key('moveTo.$title'),
              onPressed: () => Navigator.of(context).pop(tag),
              child: Row(
                children: [
                  Expanded(child: Text(title)),
                  if (tag == current ||
                      (tag == none && !SectionTags.isSection(current)))
                    const Icon(Icons.check_rounded, size: 18),
                ],
              ),
            ),
          const Divider(),
          SimpleDialogOption(
            key: const Key('moveTo.new'),
            onPressed: () => Navigator.of(context).pop(newSection),
            child: const Text('New section…'),
          ),
        ],
      ),
    );
    switch (choice) {
      case null:
        return;
      case newSection:
        await create(room: room);
      case none:
        await setSection(room, null);
      default:
        if (choice != current) await setSection(room, choice);
    }
  }

  Future<String?> _askName({required String title, String initial = ''}) =>
      showDialog<String>(
        context: _context,
        builder: (_) => _NameDialog(title: title, initial: initial),
      );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const Key('section.name'),
      controller: _name,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Name'),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('section.save'),
        onPressed: _submit,
        child: const Text('Save'),
      ),
    ],
  );
}
