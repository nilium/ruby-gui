#  Copyright 2014 Noel Cower
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
#  -----------------------------------------------------------------------------
#
#  driver.rb
#    Rendition driver


require 'opengl-core'
require 'snow-data'
require 'snow-math'
require 'gui/gl'


module GUI

class Driver

  ALL_STATE = %i[
    scale
    origin
    handle
    rotation
    color
  ]

  MAX_VERTICES_PER_STAGE = 65536
  DEFAULT_UV_MIN = Vec2[0.0, 0.0].freeze
  DEFAULT_UV_MAX = Vec2[1.0, 1.0].freeze


  Stage = Struct.new(
    :texture,     # Texture
    :vertices,    # BufferObject
    :faces,       # BufferObject
    :base_face,   # fixnum offset
    :base_vertex  # fixnum offset
    )


  VertexSpec = Snow::CStruct.struct do
    float    :position, 2
    float    :texcoord, 2
    float    :color, 4
  end


  FaceSpec = Snow::CStruct.struct do
    uint16_t :index, 3
  end


  FLOAT_TYPE      = Gl::GL_FLOAT
  VERTEX_STRIDE   = VertexSpec::SIZE
  POSITION_OFFSET = VertexSpec.offset_of(:position)
  POSITION_SIZE   = VertexSpec.length_of(:position)
  TEXCOORD_OFFSET = VertexSpec.offset_of(:texcoord)
  TEXCOORD_SIZE   = VertexSpec.length_of(:texcoord)
  COLOR_OFFSET    = VertexSpec.offset_of(:color)
  COLOR_SIZE      = VertexSpec.length_of(:color)

  attr_accessor :request_uniform_cb
  attr_accessor :color

  def initialize(capacity = 64, &request_uniform_cb)
    @position_attrib = 1
    @color_attrib    = 2
    @texcoord_attrib = 3
    @vertices        = nil
    @faces           = nil
    @rotation        = 0.0
    @scale           = Snow::Vec2[1.0, 1.0]
    @origin          = Snow::Vec2[0.0, 0.0]
    @handle          = Snow::Vec2[0.0, 1.0]
    @color           = Color[1.0, 1.0, 1.0, 1.0]
    @transform       = Snow::Mat3[]
    @temp_transform  = Snow::Mat3[]
    @transform_dirty = true
    @temp_vectors    = Snow::Vec3Array[4]
    @stages          = []
    @state           = []
    @request_uniform_cb = request_uniform_cb
    @view_size       = Vec2[0.0, 0.0]
    ensure_capacity(capacity * 3, capacity)
  end

  def push_state(*states)
    states = ALL_STATE if states.empty?
    @state << (states & ALL_STATE).each_with_object({}) do |e, h|
      prev_state = __send__(e)
      h[e] =
        case prev_state
        when Fixnum, Float then prev_state
        else
          if prev_state.respond_to?(:dup)
            prev_state.dup
          else
            prev_state
          end
        end
    end
    if block_given?
      last = @state.length - 1
      begin
        yield self
      ensure
        pop_state until @state.length == last
      end
    else
      self
    end
  end

  def pop_state
    raise "Driver state stack underflow" if @state.empty?
    @state.pop.each { |k, v| __send__(:"#{k}=", v) }
    self
  end

  def scale(output = nil)
    @scale.copy(output)
  end

  def scale=(value)
    @transform_dirty = value != @scale
    value.copy(@scale)
    value
  end

  def rotation
    @rotation
  end

  def rotation=(value)
    @transform_dirty = value != @rotation
    @rotation = value
    value
  end

  def origin(output = nil)
    @origin.copy(output)
  end

  def origin=(value)
    value.copy(@origin)
  end

  def handle(output = nil)
    @handle.copy(output)
  end

  def handle=(value)
    value.copy(@handle)
  end

  #
  # Ensures that the vertex and index arrays are both large enough to hold at
  # least `capacity` faces.
  #
  def ensure_capacity(vertex_capacity, index_capacity)
    @vertices = self.class.ensure_capacity_of_array(
      @vertices, vertex_capacity, VertexSpec::Array
      )

    @faces = self.class.ensure_capacity_of_array(
      @faces, index_capacity, FaceSpec::Array
      )
  end

  def self.ensure_capacity_of_array(ary, new_capacity, klass = nil)
    if ary
      capacity = ary.length
      return ary if capacity >= new_capacity

      capacity *= 2
      new_capacity = capacity if new_capacity < capacity

      ary.resize! new_capacity
    elsif klass
      klass.new(new_capacity.abs)
    end
  end

  def clear
    @stages.clear
  end

  def transform
    if @transform_dirty
      @transform.load_identity.
        scale!(@scale[0], -@scale[1], 1.0).
        multiply_mat3!(
          Mat3.angle_axis(
            @rotation,
            @temp_vectors[0].set(0.0, 0.0, -1.0),
            @temp_transform
            )
          )
      @transform_dirty = false
    end

    @transform
  end

  def build_vertex_array(
    vertex_buffer, index_buffer,
    position_attrib: 1,
    color_attrib: 2,
    texcoord_attrib: 3,
    vertex_offset: 0
    )
    VertexArrayObject.new.bind do |vao|
      vertex_buffer.bind Gl::GL_ARRAY_BUFFER
      index_buffer.bind Gl::GL_ELEMENT_ARRAY_BUFFER

      position_offset = vertex_offset + POSITION_OFFSET
      color_offset    = vertex_offset + COLOR_OFFSET
      texcoord_offset = vertex_offset + TEXCOORD_OFFSET

      if position_attrib
        Gl.glEnableVertexAttribArray(position_attrib)
        Gl.glVertexAttribPointer(
          position_attrib,
          POSITION_SIZE,
          FLOAT_TYPE,
          Gl::GL_FALSE,
          VERTEX_STRIDE,
          position_offset
          )
      end

      if color_attrib
        Gl.glEnableVertexAttribArray color_attrib
        Gl.glVertexAttribPointer(
          color_attrib,
          COLOR_SIZE,
          FLOAT_TYPE,
          Gl::GL_FALSE,
          VERTEX_STRIDE,
          color_offset
          )
      end

      if texcoord_attrib
        Gl.glEnableVertexAttribArray texcoord_attrib
        Gl.glVertexAttribPointer(
          texcoord_attrib,
          TEXCOORD_SIZE,
          FLOAT_TYPE,
          Gl::GL_FALSE,
          VERTEX_STRIDE,
          texcoord_offset
          )
      end

      vao
    end
  end

  # Public: Draws a quad with the given material, position, size, color, with
  # texture coordinates spanning uv_min (bottom-left) to uv_max (top-right).
  #
  # material - The material to draw the quad with. May be nil, in which case
  #            the Driver will assume you have some way to guarantee this is
  #            drawn correctly. In general, never pass a nil material unless
  #            everything will have a nil material and all primitives share the
  #            same drawing properties/state.
  # position - The position to draw the quad at. This is affected by both the
  #            Driver's origin and handle. Scale and rotation will not affect
  #            this, though a sufficiently off-center handle can cause a quad
  #            to rotate around its position. There is no unit with which to
  #            measure this and it is dependent on your projection and world
  #            matrices.
  # size     - The size of the quad. There is no given unit of measurement and
  #            how size is interpreted is dependent on your projection and
  #            world matrices.
  # color    - The integer color of the quad in 8-bits-per-channel RGBA.
  #            Defaults to an opaque white color (0xFFFFFFFF).
  # uv_min   - The minimum UV coordinates of the quad -- this represents the
  #            bottom-left region of the quad's texture coordinates. Defaults
  #            to [0, 0], or DEFAULT_UV_MIN.
  # uv_max   - The maximum UV coordinates of the quad -- this represents the
  #            top-right region of the quad's texture coordinates. Defaults to
  #            [1, 1], or DEFAULT_UV_MAX.
  #
  # Raises ArgumentError if position or size are nil.
  # Returns self.
  def draw_quad(
    texture, position, size,
    color: nil,
    uv_min: DEFAULT_UV_MIN,
    uv_max: DEFAULT_UV_MAX
    )

    color ||= @color

    raise ArgumentError, "position is nil" unless position
    raise ArgumentError, "size is nil"     unless size

    uv_min ||= DEFAULT_UV_MIN
    uv_max ||= DEFAULT_UV_MAX
    transform = self.transform
    stage = stage_for(texture)
    ensure_capacity(stage.base_vertex + stage.vertices + 4,
                    stage.base_vertex + stage.vertices + 6)

    adjusted_pos = position.add(@origin, @temp_vectors[0])
    top_left     = @handle.multiply(size, @temp_vectors[1]).negate!
    bottom_right = size.add(top_left, @temp_vectors[2])

    vertex_index = stage.base_vertex + stage.vertices
    v0 = @vertices[vertex_index    ]
    v1 = @vertices[vertex_index + 1]
    v2 = @vertices[vertex_index + 2]
    v3 = @vertices[vertex_index + 3]

    temp_vec = @temp_vectors[3]
    vertex_pos = adjusted_pos.add(
      transform.rotate_vec3(top_left, temp_vec), temp_vec)

    v0.set_position(temp_vec[0], 0)
    v0.set_position(temp_vec[1], 1)
    v0.set_texcoord(uv_min[0], 0)
    v0.set_texcoord(uv_max[1], 1)
    v0.set_color(color.x, 0)
    v0.set_color(color.y, 1)
    v0.set_color(color.z, 2)
    v0.set_color(color.w, 3)

    vertex_pos = adjusted_pos.add(
      transform.rotate_vec3(
        temp_vec.set(bottom_right[0], top_left[1], 0.0), temp_vec), temp_vec)

    v1.set_position(temp_vec[0], 0)
    v1.set_position(temp_vec[1], 1)
    v1.set_texcoord(uv_max[0], 0)
    v1.set_texcoord(uv_max[1], 1)
    v1.set_color(color.x, 0)
    v1.set_color(color.y, 1)
    v1.set_color(color.z, 2)
    v1.set_color(color.w, 3)

    vertex_pos = adjusted_pos.add(
      transform.rotate_vec3(bottom_right, temp_vec), temp_vec)

    v2.set_position(temp_vec[0], 0)
    v2.set_position(temp_vec[1], 1)
    v2.set_texcoord(uv_max[0], 0)
    v2.set_texcoord(uv_min[1], 1)
    v2.set_color(color.x, 0)
    v2.set_color(color.y, 1)
    v2.set_color(color.z, 2)
    v2.set_color(color.w, 3)

    vertex_pos = adjusted_pos.add(
      transform.rotate_vec3(
        temp_vec.set(top_left[0], bottom_right[1], 0.0), temp_vec), temp_vec)

    v3.set_position(temp_vec[0], 0)
    v3.set_position(temp_vec[1], 1)
    v3.set_texcoord(uv_min[0], 0)
    v3.set_texcoord(uv_min[1], 1)
    v3.set_color(color.x, 0)
    v3.set_color(color.y, 1)
    v3.set_color(color.z, 2)
    v3.set_color(color.w, 3)

    vertex_index = stage.vertices
    face_index = stage.base_face + stage.faces
    face = @faces[face_index]
    face.set_index(vertex_index    , 0)
    face.set_index(vertex_index + 1, 1)
    face.set_index(vertex_index + 2, 2)
    face = @faces[face_index + 1]
    face.set_index(vertex_index + 2, 0)
    face.set_index(vertex_index + 3, 1)
    face.set_index(vertex_index    , 2)

    stage.vertices += 4
    stage.faces += 6

    self
  end

  def vertex_data_size
    stage = @stages.last
    ((stage && (stage.base_vertex + stage.vertices)) || 0) * VertexSpec::SIZE
  end

  def index_data_size
    stage = @stages.last
    ((stage && (stage.base_face + stage.faces * 3)) || 0) / 6 * VertexSpec::SIZE
  end

  def flush_data_to(
    vertex_buffer: nil,
    vertices_offset: 0,
    index_buffer: nil,
    indices_offset: 0
    )

    vertex_buffer.bind(Gl::GL_ARRAY_BUFFER) do
      Gl.glBufferSubData(
        Gl::GL_ARRAY_BUFFER,
        vertices_offset,
        vertex_data_size(),
        @vertices.address)
    end

    index_buffer.bind(Gl::GL_ELEMENT_ARRAY_BUFFER) do
      Gl.glBufferSubData(
        Gl::GL_ELEMENT_ARRAY_BUFFER,
        indices_offset,
        index_data_size(),
        @faces.address)
    end
  end

  # Takes a request_uniform_cb method so the texture unit can be set
  def draw_stages(vao, indices_offset: 0)
    raise "Invalid VAO" unless vao && vao.name != 0

    Gl.glActiveTexture(Gl::GL_TEXTURE0)
    Texture.preserve_binding(Gl::GL_TEXTURE_2D) do
      vao.bind do
        @stages.each do |stage|
          # GUI.assert_nonzero_gl_binding(Gl::GL_CURRENT_PROGRAM)

          texture = stage.texture

          offset = indices_offset + stage.base_face * 2

          if texture
            texture.bind(Gl::GL_TEXTURE_2D)
            diff_loc = @request_uniform_cb.call(:diffuse)
            Gl.glUniform1i(diff_loc, 0)
          end

          next unless stage.faces > 0

          Gl.glDrawElementsBaseVertex(
            Gl::GL_TRIANGLES,
            stage.faces * 3,
            Gl::GL_UNSIGNED_SHORT,
            offset,
            stage.base_vertex
            )
        end
      end
    end
  end

  def stage_for(texture, vertices_needed: 4)
    warn "nil texture for draw stage" if texture.nil?

    base_vertex = 0
    base_face = 0

    if (current_stage = @stages.last)
      if current_stage.texture == texture &&
         current_stage.vertices + vertices_needed <= MAX_VERTICES_PER_STAGE
        return current_stage
      end

      base_vertex = current_stage.base_vertex + current_stage.vertices
      base_face  = current_stage.base_face + current_stage.faces
    end

    new_stage = Stage.new(texture, 0, 0, base_vertex, base_face)
    @stages << new_stage
    new_stage
  end
  private :stage_for

end # Driver


class BufferedDriver < Driver

  private :flush_data_to
  private :ensure_capacity
  private :build_vertex_array

  def initialize(
    capacity = 64,
    position_attrib: 1,
    color_attrib: 2,
    texcoord_attrib: 3,
    &request_uniform_cb
    )
    super(capacity, &request_uniform_cb)

    vbo = BufferObject.new
    ibo = BufferObject.new

    vbo.target = Gl::GL_ARRAY_BUFFER
    ibo.target = Gl::GL_ELEMENT_ARRAY_BUFFER

    ObjectSpace.define_finalizer(self) { destroy }

    @vertex_buffer          = vbo
    @index_buffer           = ibo
    @vertex_buffer_capacity = 0
    @index_buffer_capacity  = 0
    @vao                    = nil
    @position_attrib        = position_attrib
    @color_attrib           = color_attrib
    @texcoord_attrib        = texcoord_attrib
    @refresh_needed         = false

  end

  def destroy
    @vertex_buffer.release { @vertex_buffer = nil }
    @index_buffer.release { @index_buffer = nil }
    @vao.release { @vao = nil } if @vao
  end

  def self.ensure_buffer_object_capacity(buffer, current_capacity, new_capacity)
    return current_capacity if new_capacity <= current_capacity

    current_capacity *= 2
    new_capacity = current_capacity if new_capacity < current_capacity

    buffer.bind do
      Gl.glBufferData(buffer.target, new_capacity, 0, Gl::GL_DYNAMIC_DRAW)
    end

    new_capacity
  end

  def draw_quad(
    material, position, size,
    color: nil,
    uv_min: Driver::DEFAULT_UV_MIN,
    uv_max: Driver::DEFAULT_UV_MAX
    )
    @refresh_needed = true
    super
  end

  def ensure_buffer_capacity(vertices_capacity: nil, indices_capacity: nil)
    if vertices_capacity
      @vertex_buffer_capacity = self.class.ensure_buffer_object_capacity(
        @vertex_buffer,
        @vertex_buffer_capacity,
        vertices_capacity
        )
    end

    if indices_capacity
      @index_buffer_capacity = self.class.ensure_buffer_object_capacity(
        @index_buffer,
        @index_buffer_capacity,
        indices_capacity
        )
    end
  end

  def draw_stages
    if @refresh_needed
      ensure_buffer_capacity(
        vertices_capacity: self.vertex_data_size,
        indices_capacity: self.index_data_size
        )

      flush_data_to(
        vertex_buffer: @vertex_buffer,
        index_buffer: @index_buffer
        )

      if @vao.nil?
        @vao = build_vertex_array(
          @vertex_buffer, @index_buffer,
          position_attrib: @position_attrib,
          color_attrib:    @color_attrib,
          texcoord_attrib: @texcoord_attrib
          )
      end
    end

    super(@vao) unless @stages.empty?
  end

end # BufferedDriver

end
