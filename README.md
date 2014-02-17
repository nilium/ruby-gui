GUI Gem
==============================================================================

A gem for creating Ruby applications with GUI interfaces by using GLFW3 for windowing and OpenGL for rendition and everything else completely custom because sanity is for the weak.



Notes
------------------------------------------------------------------------------

Currently experimental. Requires snow-math to be compiled with --use-float due to current use of glUniform assuming 32-bit float data. It may be prudent, later, to write a wrapper uniform function to handle this, or simply copy the UniformHash code from my gametools gem.


License
------------------------------------------------------------------------------

The GUI gem is licensed under the Apache 2.0 license. You should have received a copy of the license with the gem in a COPYING file, though it may also be read at <http://www.apache.org/licenses/LICENSE-2.0>.
