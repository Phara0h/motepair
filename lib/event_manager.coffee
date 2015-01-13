{TextEditor} = require('atom')
WsEmitClient = require('./ws/ws-emit-client.js')
Fsm          = require('./fsm.js')

class EventManager
  constructor: (atom) ->

  createSocketConnection: (address, portNumber) ->
    @remoteClient = new WsEmitClient("ws://#{ address }:#{ portNumber }")
    @fsm =  new Fsm({ws: @remoteClient})
    @listen()

  listen: ->

    @remoteClient.on 'open', =>
      sessionId = atom.config.get('atom-remote-pair.sessionId')
      @remoteClient.write('create-session', { sessionId: sessionId })

    @remoteClient.on 'save-file', (event) =>
      @fsm.transition("remoteFileChanging")
      @fsm.handle("saveFile", event, atom)

    @remoteClient.on 'close-file', (event) =>
      @fsm.transition("remoteFileChanging")
      @fsm.handle("closeFile", event, atom)

    @remoteClient.on 'change-file', (event) =>
      @fsm.transition("remoteFileChanging")
      @fsm.handle("changeFile", event, atom)

    @remoteClient.on 'open-file', (event) =>
      @fsm.transition("remoteFileChanging")
      @fsm.handle("changeFile", event, atom)

    @remoteClient.on 'change', (event) =>
      for editor in atom.workspace.getPaneItems() when editor.getPath().indexOf(event.file) >= 0
        @fsm.transition("remoteChanging")
        @fsm.handle("remoteChange", editor, event.change)

    @remoteClient.on 'selection', (event) =>
      for editor in atom.workspace.getPaneItems() when editor.getPath().indexOf(event.file) >= 0
        @fsm.transition("remoteSelecting")
        @fsm.handle("remoteSelection", editor, event)
        setTimeout =>
          @fsm.transition("localSelecting")
        , 300


    atom.workspaceView.command "remote-pair:action", => @action()
    @project = atom.project

    atom.workspace.observeTextEditors (editor) =>

      editor.backspace = (args) =>
        editor.emit('will-backspace', args)
        TextEditor.prototype.backspace.call(editor, args)

      editor.on 'will-backspace', (event) =>
        @fsm.transition("localChanging")

      editor.onDidSave (event) =>
        @fsm.handle("fileAction", "save-file", @project.relativize(event.path))
        @fsm.transition("localChanging")

      editor.onDidChangeCursorPosition (event) =>
        if event.textChanged
          @fsm.transition("localChanging")
        else
          setTimeout =>
            @fsm.transition("localSelecting")
          , 300

      editor.onDidChangeSelectionRange (event) =>
        @fsm.handle("localSelection", atom, editor, event)

      editor.onWillInsertText (event) =>
        @fsm.transition("localChanging")

      buffer = editor.getBuffer()

      buffer.onDidChange (event) =>
        @fsm.handle('localChange', atom, editor, event)

    atom.workspace.onDidOpen (event) =>
      @fsm.handle 'fileAction', 'change-file', @project.relativize(event.uri)
      setTimeout =>
        @fsm.transition("localChanging")
      , 300

    atom.workspace.onDidChangeActivePaneItem (event) =>
      return unless event?
      @fsm.handle 'fileAction', 'change-file', @project.relativize(event.getPath())
      setTimeout =>
        @fsm.transition("localChanging")
      , 300

    atom.workspace.onWillDestroyPaneItem (event) =>
      @fsm.handle 'fileAction', 'close-file', @project.relativize(event.item.getPath())
      setTimeout =>
        @fsm.transition("localChanging")
      , 300

module.exports = EventManager
