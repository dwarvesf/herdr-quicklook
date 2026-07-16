# demo/

GIFs are recorded from a real herdr session with [vhs](https://github.com/charmbracelet/vhs):

```sh
cd <a repo checkout>            # relative paths in the tape resolve against it
vhs demo/preview.tape           # writes demo/preview.gif
```

Notes for re-recording:

- The tapes launch `herdr --session vhs-demo` with the `HERDR_*` env vars stripped;
  without that, running vhs from inside a herdr pane trips the "nested herdr is
  disabled" guard.
- The recording attaches a REAL herdr server session named `vhs-demo`; it stays on
  the server afterwards (harmless; close its pane when you notice it).
- `viewer.tape` needs the herdr-file-viewer plugin installed on the recording host.
