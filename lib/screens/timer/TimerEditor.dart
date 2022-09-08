// Copyright 2020 Kenton Hamaluik
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_datetime_picker/flutter_datetime_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:timecop/blocs/projects/bloc.dart';
import 'package:timecop/blocs/settings/settings_bloc.dart';
import 'package:timecop/blocs/timers/bloc.dart';
import 'package:timecop/components/ProjectColour.dart';
import 'package:timecop/l10n.dart';
import 'package:timecop/models/project.dart';
import 'package:timecop/models/timer_entry.dart';
import 'package:timecop/models/clone_time.dart';

class TimerEditor extends StatefulWidget {
  final TimerEntry timer;
  TimerEditor({Key? key, required this.timer}) : super(key: key);

  @override
  _TimerEditorState createState() => _TimerEditorState();
}

class _TimerEditorState extends State<TimerEditor> {
  TextEditingController? _descriptionController;
  TextEditingController? _notesController;
  String? _notes;

  DateTime? _startTime;
  DateTime? _endTime;

  DateTime? _oldStartTime;
  DateTime? _oldEndTime;

  Project? _project;
  late FocusNode _descriptionFocus;
  final _formKey = GlobalKey<FormState>();
  late Timer _updateTimer;
  late StreamController<DateTime> _updateTimerStreamController;

  static final DateFormat _dateFormat = DateFormat("EE, MMM d, yyyy h:mma");

  late ProjectsBloc _projectsBloc;

  @override
  void initState() {
    super.initState();
    _projectsBloc = BlocProvider.of<ProjectsBloc>(context);
    _notes = widget.timer.notes ?? "";
    _descriptionController =
        TextEditingController(text: widget.timer.description);
    _notesController = TextEditingController(text: _notes);
    _startTime = widget.timer.startTime;
    _endTime = widget.timer.endTime;
    _project = BlocProvider.of<ProjectsBloc>(context)
        .getProjectByID(widget.timer.projectID);
    _descriptionFocus = FocusNode();
    _updateTimerStreamController = StreamController();
    _updateTimer = Timer.periodic(Duration(seconds: 1),
        (_) => _updateTimerStreamController.add(DateTime.now()));
  }

  @override
  void dispose() {
    _descriptionController!.dispose();
    _descriptionFocus.dispose();
    _updateTimer.cancel();
    _updateTimerStreamController.close();
    super.dispose();
  }

  void setStartTime(DateTime dt) {
    setState(() {
      // adjust the end time to keep a constant duration if we would somehow make the time negative
      if (_oldEndTime != null && dt.isAfter(_oldStartTime!)) {
        Duration d = _oldEndTime!.difference(_oldStartTime!);
        _endTime = dt.add(d);
      }
      _startTime = dt;
    });
  }

  @override
  Widget build(BuildContext context) {
    final SettingsBloc settingsBloc = BlocProvider.of<SettingsBloc>(context);
    final TimersBloc timers = BlocProvider.of<TimersBloc>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10N.of(context).tr.editTimer),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BlocBuilder<ProjectsBloc, ProjectsState>(
              builder: (BuildContext context, ProjectsState projectsState) =>
                  Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: DropdownButton(
                        value: (_project?.archived ?? true) ? null : _project,
                        underline: Container(),
                        elevation: 0,
                        onChanged: (Project? newProject) {
                          setState(() {
                            _project = newProject;
                          });
                        },
                        items: <DropdownMenuItem<Project>>[
                          DropdownMenuItem<Project>(
                            value: null,
                            child: Row(
                              children: <Widget>[
                                ProjectColour(project: null),
                                Padding(
                                  padding: EdgeInsets.fromLTRB(8.0, 0, 0, 0),
                                  child: Text(L10N.of(context).tr.noProject,
                                      style: TextStyle(
                                          color:
                                              Theme.of(context).disabledColor)),
                                ),
                              ],
                            ),
                          )
                        ]
                            .followedBy(projectsState.projects
                                .where((p) => !p.archived)
                                .map((Project project) =>
                                    DropdownMenuItem<Project>(
                                      value: project,
                                      child: Row(
                                        children: <Widget>[
                                          ProjectColour(
                                            project: project,
                                          ),
                                          Padding(
                                            padding: EdgeInsets.fromLTRB(
                                                8.0, 0, 0, 0),
                                            child: Text(project.name),
                                          ),
                                        ],
                                      ),
                                    )))
                            .toList(),
                      )),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: settingsBloc.state.autocompleteDescription
                  ? TypeAheadField<String?>(
                      direction: AxisDirection.down,
                      textFieldConfiguration: TextFieldConfiguration(
                        controller: _descriptionController,
                        autocorrect: true,
                        decoration: InputDecoration(
                          labelText: L10N.of(context).tr.description,
                          hintText: L10N.of(context).tr.whatWereYouDoing,
                        ),
                      ),
                      noItemsFoundBuilder: (context) => ListTile(
                          title: Text(L10N.of(context).tr.noItemsFound),
                          enabled: false),
                      itemBuilder: (BuildContext context, String? desc) =>
                          ListTile(title: Text(desc!)),
                      onSuggestionSelected: (String? description) =>
                          _descriptionController!.text = description!,
                      suggestionsCallback: (pattern) async {
                        if (pattern.length < 2) return [];

                        List<String?> descriptions = timers.state.timers
                            .where((timer) => timer.description != null)
                            .where((timer) => !(_projectsBloc
                                    .getProjectByID(timer.projectID)
                                    ?.archived ==
                                true))
                            .where((timer) =>
                                timer.description
                                    ?.toLowerCase()
                                    .contains(pattern.toLowerCase()) ??
                                false)
                            .map((timer) => timer.description)
                            .toSet()
                            .toList();
                        return descriptions;
                      },
                    )
                  : TextFormField(
                      controller: _descriptionController,
                      autocorrect: true,
                      decoration: InputDecoration(
                        labelText: L10N.of(context).tr.description,
                        hintText: L10N.of(context).tr.whatWereYouDoing,
                      ),
                    ),
            ),
            Slidable(
              endActionPane: ActionPane(
                  motion: const DrawerMotion(),
                  extentRatio: 0.15,
                  children: <Widget>[
                    SlidableAction(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      foregroundColor:
                          Theme.of(context).colorScheme.onSecondary,
                      icon: FontAwesomeIcons.clock,
                      onPressed: (_) {
                        _oldStartTime = _startTime;
                        _oldEndTime = _endTime;
                        setStartTime(DateTime.now());
                      },
                    ),
                  ]),
              child: ListTile(
                title: Text(L10N.of(context).tr.startTime),
                trailing: Text(_dateFormat.format(_startTime!)),
                onTap: () async {
                  _oldStartTime = _startTime?.clone();
                  _oldEndTime = _endTime?.clone();
                  DateTime? newStartTime =
                      await DatePicker.showDateTimePicker(context,
                          currentTime: _startTime,
                          maxTime: _endTime == null ? DateTime.now() : null,
                          onChanged: (DateTime dt) => setStartTime(dt),
                          onConfirm: (DateTime dt) => setStartTime(dt),
                          theme: DatePickerTheme(
                            cancelStyle: Theme.of(context).textTheme.button!,
                            doneStyle: Theme.of(context).textTheme.button!,
                            itemStyle: Theme.of(context).textTheme.bodyText2!,
                            backgroundColor:
                                Theme.of(context).colorScheme.surface,
                          ));

                  // if the user cancelled, this should be null
                  if (newStartTime == null) {
                    setState(() {
                      _startTime = _oldStartTime;
                      _endTime = _oldEndTime;
                    });
                  }
                },
              ),
            ),
            Slidable(
              endActionPane: ActionPane(
                  motion: const DrawerMotion(),
                  extentRatio: 0.15,
                  children: _endTime == null
                      ? <Widget>[
                          SlidableAction(
                            backgroundColor:
                                Theme.of(context).colorScheme.secondary,
                            foregroundColor:
                                Theme.of(context).colorScheme.onSecondary,
                            icon: FontAwesomeIcons.clock,
                            onPressed: (_) =>
                                setState(() => _endTime = DateTime.now()),
                          ),
                        ]
                      : <Widget>[
                          SlidableAction(
                            backgroundColor:
                                Theme.of(context).colorScheme.secondary,
                            foregroundColor:
                                Theme.of(context).colorScheme.onSecondary,
                            icon: FontAwesomeIcons.clock,
                            onPressed: (_) =>
                                setState(() => _endTime = DateTime.now()),
                          ),
                          SlidableAction(
                            backgroundColor: Theme.of(context).errorColor,
                            foregroundColor:
                                Theme.of(context).colorScheme.onSecondary,
                            icon: FontAwesomeIcons.circleMinus,
                            onPressed: (_) {
                              setState(() {
                                _endTime = null;
                              });
                            },
                          )
                        ]),
              child: ListTile(
                title: Text(L10N.of(context).tr.endTime),
                trailing: Text(
                    _endTime == null ? "—" : _dateFormat.format(_endTime!)),
                onTap: () async {
                  _oldEndTime = _endTime?.clone();
                  DateTime? newEndTime = await DatePicker.showDateTimePicker(
                      context,
                      currentTime: _endTime,
                      minTime: _startTime,
                      onChanged: (DateTime dt) => setState(() => _endTime = dt),
                      onConfirm: (DateTime dt) => setState(() => _endTime = dt),
                      theme: DatePickerTheme(
                        cancelStyle: Theme.of(context).textTheme.button!,
                        doneStyle: Theme.of(context).textTheme.button!,
                        itemStyle: Theme.of(context).textTheme.bodyText2!,
                        backgroundColor: Theme.of(context).colorScheme.surface,
                      ));

                  // if the user cancelled, this should be null
                  if (newEndTime == null) {
                    setState(() {
                      _endTime = _oldEndTime;
                    });
                  }
                },
              ),
            ),
            StreamBuilder(
              initialData: DateTime.now(),
              stream: _updateTimerStreamController.stream,
              builder:
                  (BuildContext context, AsyncSnapshot<DateTime> snapshot) =>
                      ListTile(
                title: Text(L10N.of(context).tr.duration),
                trailing: Text(
                  TimerEntry.formatDuration(_endTime == null
                      ? snapshot.data!.difference(_startTime!)
                      : _endTime!.difference(_startTime!)),
                  style:
                      TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            ),
            Slidable(
              endActionPane: ActionPane(
                  motion: const DrawerMotion(),
                  extentRatio: 0.15,
                  children: <Widget>[
                    SlidableAction(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      foregroundColor:
                          Theme.of(context).colorScheme.onSecondary,
                      icon: FontAwesomeIcons.penToSquare,
                      onPressed: (_) async => await _editNotes(context),
                    ),
                  ]),
              child: ListTile(
                title: Text("Notes"),
                onTap: () async => await _editNotes(context),
              ),
            ),
            Expanded(
                child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Markdown(data: _notes!))),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: Key("saveDetails"),
        child: Stack(
          // shenanigans to properly centre the icon (font awesome glyphs are variable
          // width but the library currently doesn't deal with that)
          fit: StackFit.expand,
          children: <Widget>[
            Positioned(
              top: 14,
              left: 16,
              child: Icon(FontAwesomeIcons.check),
            )
          ],
        ),
        onPressed: () async {
          bool valid = _formKey.currentState!.validate();
          if (!valid) return;

          TimerEntry timer = TimerEntry(
            id: widget.timer.id,
            startTime: _startTime!,
            endTime: _endTime,
            projectID: _project?.id,
            description: _descriptionController!.text.trim(),
            notes: _notes!.isEmpty ? null : _notes,
          );

          timers.add(EditTimer(timer));
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Future<void> _editNotes(BuildContext context) async {
    print("notes: " + _notes!);
    _notesController!.text = _notes!;
    String? n = await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text("Notes"),
            content: TextFormField(
              controller: _notesController,
              autofocus: true,
              autocorrect: true,
              maxLines: null,
              expands: true,
              smartDashesType: SmartDashesType.enabled,
              smartQuotesType: SmartQuotesType.enabled,
              onSaved: (String? n) => Navigator.of(context).pop(n),
            ),
            actions: <Widget>[
              TextButton(
                  child: Text(L10N.of(context).tr.cancel),
                  onPressed: () => Navigator.of(context).pop()),
              TextButton(
                  style: TextButton.styleFrom(
                      primary: Theme.of(context).colorScheme.secondary),
                  onPressed: () =>
                      Navigator.of(context).pop(_notesController!.text),
                  child: Text(
                    L10N.of(context).tr.save,
                  ))
            ],
          );
        });
    if (n != null) {
      setState(() {
        _notes = n.trim();
      });
    }
  }
}
