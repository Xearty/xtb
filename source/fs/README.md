# fs

`import xtb.fs;` exposes filesystem-domain APIs: borrowed paths, files,
directory operations, metadata, and file-backed read-only mappings. The domain
owns portable filesystem concepts while its platform backends consume precise
low-level interfaces such as `xtb.os.posix`.

See [`fs_demo.d`](../../examples/fs_demo.d).
