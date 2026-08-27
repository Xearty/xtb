# fs

`import xtb.fs;` exposes filesystem-domain APIs: borrowed paths, files,
directory operations, metadata, and file-backed read-only mappings. The domain
owns portable filesystem concepts while delegating native mechanisms and error
translation to `xtb.os`.

See [`fs_demo.d`](../../examples/fs_demo.d).
