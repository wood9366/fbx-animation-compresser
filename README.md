# Fbx Animation Compresser
Change animation data precision.

Reference:

* [Fbx Format](https://code.blender.org/2013/08/fbx-binary-file-format-specification/)
* [Animation Compress](https://gameinstitute.qq.com/community/detail/103951)

Usage:

fbx_animation_compresser --fbx [fbx file path] --precision [limitation of precision] --debug

* *--precision* default value 3, accurate to 3 decimal places. no matter value input, value will be limited in [0,10].
* *--debug* print fbx information output when parse fbx file.
