# dllart calc example

Standalone example project for local `dllart` development.

## Run

From repository root:

```bash
dart pub get
(cd example/calc && dart pub get)
dart run dllart build --config example/calc/dllart.json
```

Then run validation clients:

```bash
scripts/smoke_test.sh
```
