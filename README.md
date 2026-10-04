Hi all.

This is a work-in-progress rework of a 96Kb .kkrieger game
created by the Farbrausch team. So far I have managed to do the following:

- Reverse-engineered KKrunchy executable packing format and created
an unpacked version. You can find that part in the KKrunchy folder.
- ... More to follow

This repository does not include the original .kkrieger executable
or the unpacked executable. You can get original one from
pouet.net link below. For the unpacked version I plan to create the
Python unpacker, but it is not ready yet. 

I want to explicitly mention that this is not my original work,
and it was originally created by the Farbrausch team.
The original version of the game can be downloaded from pouet.net
(https://www.pouet.net/prod.php?which=12036).

I only reverse-engineered part of this game and created source code 
for KKrunchy unpacker. The original sources are located at the
link https://github.com/farbrausch/fr_public - and it is mentioned
there that "All of this is released either under a BSD license
or put in the public domain (stated per project)". The 
reconstructed KKrunchy unpacker is released under the same 
terms as the original KKrunchy sources (public domain), 
as stated in the fr_public repository in the "kkrunchy" folder, 
(although source code in fr_public repository is not quite the same 
as in original .kkrieger release due to different versions).

Enjoy!
