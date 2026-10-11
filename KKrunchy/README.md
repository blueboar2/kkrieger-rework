This folder contains four files. Two of them contain reconstructed
KKrunchy unpacking code inside KKrieger:

- kkrunchy_unpacker_stage1.asm - first step of KKrunchy unpacking,
mainly responsible for decompression and import resolution
- kkrunchy_unpacker_stage2.asm - second step of KKrunchy unpacking,
mainly reconstructing the original x86 code from separate data
streams

If you don't want to bother with this code, you can use the Python
scripts just to unpack KKrieger:

- Place the pno0001.exe file in the same folder as the Python scripts.
This repository doesn't include this file, but you can get it
from pouet.net (https://www.pouet.net/prod.php?which=12036).
- Run the kkrunchy_unpacker_stage1.py script. You will receive
kkrunchy_unpacker_stage1.out with a size of 375395 bytes. It is the
result of the first unpacking stage.
- Run the kkrunchy_unpacker_stage2.py script. You will receive
kkrunchy_unpacker_stage2.out with a size of 256012 bytes. It is the
result of the second unpacking stage. It is byte-for-byte identical
to the original unpacked memory image except for the offset range 
0x1E000-0x1E0C0, where the original unpacker places the imports
but the Python scripts do not.

Enjoy!
