//  Copyright 2014 Noel Cower
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
//  ----------------------------------------------------------------------------
//
//  selector.c
//    Selector parser, implemented in C for performance reasons.
//
//    The original parser was implemented in Ruby, but pulled before adding it
//    to the repo since it was considerably slower (about 3-5ms to parse a
//    typical selector). Although typically not the bottleneck -- the lookups
//    for views should be much slower in practice -- the parser had to be fast
//    enough to be run at least a handful of times per frame. At 3-5ms, even
//    one or two uses of the parser would've shot the framerate to hell and
//    back.
//
//    So, instead, the parser is written in C, and parsing itself takes -- on
//    my system, of course -- an average of about 0.02ms for a lengthy-ish
//    selector.
//
//    I decided this is sufficient.


#include "ruby.h"

#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <assert.h>
#include <stdio.h>


/*=============================================================================
|  Sean Barrett's stretchy buffer                                             |
=============================================================================*/

/*
  stretchy buffer
  init: NULL
  free: sbfree()
  push_back: sbpush()
  size: sbcount()
  resize: sbresize()
*/
#define sbfree(a)     \
  ((a) ? free(stb__sbraw(a)),0 : 0)
#define sbpush(a,v)   \
  (stb__sbmaybegrow(a,1), (a)[stb__sbn(a)++] = (v))
#define sbcount(a)    \
  ((a) ? stb__sbn(a) : 0)
#define sbadd(a,n)    \
  (stb__sbmaybegrow(a,n), stb__sbn(a)+=(n), &(a)[stb__sbn(a)-(n)])
#define sblast(a)     \
  ((a)[stb__sbn(a)-1])
#define sbcapacity(a) \
  ((a) ? stb__sbm(a) : 0)

#include <stdlib.h>
#define stb__sbraw(a) ((int *) (a) - 2)
#define stb__sbm(a)   stb__sbraw(a)[0]
#define stb__sbn(a)   stb__sbraw(a)[1]

#define stb__sbneedgrow(a,n)  ((a)==0 || stb__sbn(a)+n >= stb__sbm(a))
#define stb__sbmaybegrow(a,n) (stb__sbneedgrow(a,(n)) ? stb__sbgrow(a,n) : 0)
#define stb__sbgrow(a,n)  stb__sbgrowf((void **) &(a), (n), sizeof(*(a)))

static void stb__sbgrowf(void **arr, int increment, int itemsize)
{
   int m = *arr ? 2*stb__sbm(*arr)+increment : increment+1;
   void *p = realloc(*arr ? stb__sbraw(*arr) : 0, itemsize * m + sizeof(int)*2);
   assert(p);
   if (p) {
      if (!*arr) ((int *) p)[1] = 0;
      *arr = (void *) ((int *) p + 2);
      stb__sbm(*arr) = m;
   }
}



/*=============================================================================
|  Types and values                                                           |
=============================================================================*/

typedef struct s_qparser
{
  const char *chars;
  int length;
  int index;
  char *buffer;
} qparser_t;


typedef struct s_qchars {
  int length;
  const char *chars;
} qchars_t;


static qchars_t const Q_WHITESPACE         = { 4,  " \t\n\r" };
static qchars_t const Q_ANY_TAG_MARK       = { 1,  "*" };
static qchars_t const Q_CONTAINS_MARK      = { 1,  "-" };
static qchars_t const Q_DECIMAL_MARK       = { 1,  "." };
static qchars_t const Q_EQUAL_MARK         = { 1,  "=" };
static qchars_t const Q_EXPONENT_MARK      = { 1,  "eE" };
static qchars_t const Q_EXP_PLUSMINUS_MARK = { 2,  "+-" };
static qchars_t const Q_GREATER_MARK       = { 1,  ">" };
static qchars_t const Q_LESSER_MARK        = { 1,  "<" };
static qchars_t const Q_NEGATION_MARK      = { 1,  "!" };
static qchars_t const Q_MINUS_MARK         = { 1,  "-" };
static qchars_t const Q_START_MULTI_TAG    = { 1,  "(" };
static qchars_t const Q_END_MULTI_TAG      = { 1,  ")" };
static qchars_t const Q_MULTI_TAG_SEP      = { 1,  "|" };
static qchars_t const Q_START_ATTR         = { 1,  "[" };
static qchars_t const Q_END_ATTR           = { 1,  "]" };
static qchars_t const Q_TAG_MARKER         = { 1,  "#" };
static qchars_t const Q_QUOTE              = { 1,  "\"" };
static qchars_t const Q_ESCAPE             = { 1,  "\\" };
static qchars_t const Q_QUOTE_OR_ESCAPE    = { 1,  "\"\\" };
static qchars_t const Q_DIRECT_FOLLOW      = { 1,  ">" };
static qchars_t const Q_DIGITS             = { 10, "0123456789" };
static qchars_t const Q_OPERATOR_CHARS     = { 7,  "#!=<>*-" };
static qchars_t const Q_NAME_BOUNDS        = { 17, " #\"|>([*!=<-])\n\t\r" };


enum {
  Q_NO = 0,
  Q_YES = 1,

  /* as arguments to accept/read */
  Q_DO_NOT_ADD_TO_BUFFER = Q_NO,
  Q_ADD_TO_BUFFER = Q_YES,

  /* as arguments to q_read_name */
  Q_AS_STRING = Q_NO,
  Q_AS_SYMBOL = Q_YES
};


typedef VALUE (qmaybefunc_t)(qparser_t *, void *);


#define LAZY_CLASS_DEF_UNDER(FNAME, UNDER, CLASSNAME, SUPERCLASS)    \
VALUE                                                                \
FNAME ()                                                             \
{                                                                    \
  static VALUE klass = Qnil;                                         \
  if (NIL_P(klass))                                                  \
    klass = rb_define_class_under((UNDER), #CLASSNAME, SUPERCLASS);  \
  return klass;                                                      \
}


#define LAZY_MODULE_DEF_UNDER(FNAME, UNDER, MODNAME)                 \
VALUE                                                                \
FNAME ()                                                             \
{                                                                    \
  static VALUE mod = Qnil;                                           \
  if (NIL_P(mod))                                                    \
    mod = rb_define_module_under((UNDER), #MODNAME);                 \
  return mod;                                                        \
}


#define LAZY_MODULE_DEF(FNAME, MODNAME)                              \
VALUE                                                                \
FNAME ()                                                             \
{                                                                    \
  static VALUE mod = Qnil;                                           \
  if (NIL_P(mod))                                                    \
    mod = rb_define_module(#MODNAME);                                \
  return mod;                                                        \
}


#define LAZY_STATIC_ID(NAME, SYM)                                    \
  static ID NAME = 0;                                                \
  if (NAME == 0) NAME = rb_intern(SYM)


static LAZY_MODULE_DEF(
  q_gui_module,
  GUI
  );

static LAZY_MODULE_DEF_UNDER(
  q_parser_module,
  q_gui_module(),
  SelectorParser
  );

static LAZY_CLASS_DEF_UNDER(
  q_selector_class,
  q_gui_module(),
  Selector,
  rb_cObject
  );

static LAZY_CLASS_DEF_UNDER(
  q_view_class_check,
  q_gui_module(),
  ViewClassCheck,
  rb_cObject
  );

static LAZY_CLASS_DEF_UNDER(
  q_view_tag_check,
  q_gui_module(),
  ViewTagCheck,
  rb_cObject
  );

static LAZY_CLASS_DEF_UNDER(
  q_view_attr_check,
  q_gui_module(),
  ViewAttrCheck,
  rb_cObject
  );


/* Operator names */
static ID q_id_equal = 0;
static ID q_id_not_equal = 0;
static ID q_id_greater = 0;
static ID q_id_greater_equal = 0;
static ID q_id_lesser = 0;
static ID q_id_lesser_equal = 0;
static ID q_id_contains = 0;
static ID q_id_trueish = 0;
static ID q_id_falseish = 0;



/*=============================================================================
|  Selector methods                                                           |
=============================================================================*/

static
int
q_selector_is_direct(VALUE selector)
{
  LAZY_STATIC_ID(direct_id, "direct");
  return RTEST(rb_funcall2(selector, direct_id, 0, NULL));
}


static
VALUE
q_selector_set_direct(VALUE selector, int direct)
{
  LAZY_STATIC_ID(direct_eq_id, "direct=");
  VALUE is_direct = direct ? Qtrue : Qfalse;
  return rb_funcall2(selector, direct_eq_id, 1, &is_direct);
}


static
VALUE
q_selector_set_succ(VALUE selector, VALUE succ)
{
  LAZY_STATIC_ID(succ_eq_id, "succ=");
  return rb_funcall2(selector, succ_eq_id, 1, &succ);
}


static
VALUE
q_selector_succ(VALUE selector)
{
  LAZY_STATIC_ID(succ_id, "succ");
  return rb_funcall2(selector, succ_id, 0, NULL);
}


static
VALUE
q_selector_attributes(VALUE selector)
{
  LAZY_STATIC_ID(attributes_id, "attributes");
  return rb_funcall2(selector, attributes_id, 0, NULL);
}



/*=============================================================================
|  Prototypes                                                                 |
=============================================================================*/

static const char *q_strnchr(const char *str, int length, int chr);
static void q_set_buf_size(qparser_t *parser, int size);
static void q_init_parser(qparser_t *parser, const char *chars, int length);
static void q_destroy_parser(qparser_t *parser);
static int q_eos(const qparser_t *parser);
static int q_peek(const qparser_t *parser);
static int q_read(qparser_t *parser, bool add_to_buffer);
static void q_clear_buf(qparser_t *parser);
static int q_accept(qparser_t *parser, qchars_t chars, int add_to_buffer);
static int q_accept_run(qparser_t *parser, qchars_t chars, int add_to_buffer);
static int q_accept_until(qparser_t *parser, qchars_t chars, int add_to_buffer);
static void q_skip_whitespace(qparser_t *parser);
static VALUE q_read_string(qparser_t *parser);
static VALUE q_read_attribute(qparser_t *parser);
static VALUE q_read_multi_class_tag(qparser_t *parser);
static VALUE q_read_single_class_tag(qparser_t *parser);
static VALUE q_read_selector(qparser_t *parser);
static VALUE q_rb_parse_selector(VALUE self, VALUE selector_rb_str);



/*=============================================================================
|  Implementations                                                            |
=============================================================================*/

static
const char *
q_strnchr(const char *str, int length, int chr)
{
  if (chr != '\0') {
    if (length > 1) {
      const char *const end_of_str = str + length;
      for (; str < end_of_str; ++str) {
        if (*str == chr) return str;
      }
    } else if (length == 1) {
      return *str == chr ? str : NULL;
    }
  }
  return NULL;
}


static
void
q_set_buf_size(qparser_t *parser, int size)
{
  int cap;

  if (!parser->buffer) {
    return;
  }

  cap = sbcapacity(parser->buffer);
  if (size > cap) {
    stb__sbmaybegrow(parser->buffer, size - cap);
  }

  stb__sbn(parser->buffer) = size;
}


static
void
q_init_parser(qparser_t *parser, const char *chars, int length)
{
  parser->chars  = chars;
  parser->length = length;
  parser->index  = 0;
  parser->buffer = NULL;
}


static
void
q_destroy_parser(qparser_t *parser)
{
  parser->chars = NULL;
  parser->length = 0;
  parser->index = 0;
  sbfree(parser->buffer);
  parser->buffer = NULL;
}


static
int
q_eos(const qparser_t *parser)
{
  return parser->index >= parser->length;
}


static
int
q_peek(const qparser_t *parser)
{
  int index = parser->index;
  return (index < parser->length)
          ? parser->chars[index]
          : 0;
}


static
int
q_read(qparser_t *parser, bool add_to_buffer)
{
  char const ch = q_peek(parser);

  if (ch) {
    ++parser->index;

    if (add_to_buffer) {
      sbpush(parser->buffer, ch);
    }
  }

  return ch;
}


static
void
q_clear_buf(qparser_t *parser)
{
  q_set_buf_size(parser, 0);
}


static
int
q_accept(qparser_t *parser, qchars_t chars, int add_to_buffer)
{
  if (q_strnchr(chars.chars, chars.length, q_peek(parser))) {
    return q_read(parser, add_to_buffer);
  }
  return 0;
}


static
int
q_accept_run(qparser_t *parser, qchars_t chars, int add_to_buffer)
{
  int accepted = 0;
  while (q_accept(parser, chars, add_to_buffer)) {
    ++accepted;
  }
  return accepted;
}


static
int
q_accept_until(qparser_t *parser, qchars_t chars, int add_to_buffer)
{
  int accepted = 0;
  while (!q_eos(parser)
         && !q_strnchr(chars.chars, chars.length, q_peek(parser))) {
    q_read(parser, add_to_buffer);
    ++accepted;
  }
  return accepted;
}


static
void
q_skip_whitespace(qparser_t *parser)
{
  for (;;) {
    switch (q_peek(parser)) {
    case ' ': case '\t': case '\r': case '\n':
      q_read(parser, Q_DO_NOT_ADD_TO_BUFFER);
      break;

    default:
      return;
    }
  }
}


static
VALUE
q_read_name(qparser_t *parser, int as_symbol)
{
  if (q_accept_until(parser, Q_NAME_BOUNDS, Q_ADD_TO_BUFFER)) {
    VALUE name =
      as_symbol
      ? ID2SYM(rb_intern2(parser->buffer, sbcount(parser->buffer)))
      : rb_str_new(parser->buffer, sbcount(parser->buffer));

    q_clear_buf(parser);
    return name;
  }
  return Qnil;
}


static
VALUE
q_read_string(qparser_t *parser)
{
  /*
    assumes the string doesn't depend on escaping anything other than a
    literal character
  */
  if (q_accept(parser, Q_QUOTE, Q_DO_NOT_ADD_TO_BUFFER)) {
    for (;;) {
      q_accept_until(parser, Q_QUOTE_OR_ESCAPE, Q_ADD_TO_BUFFER);

      if (q_accept(parser, Q_ESCAPE, Q_DO_NOT_ADD_TO_BUFFER)) {
        q_read(parser, Q_ADD_TO_BUFFER);
      } else {
        break;
      }
    }

    if (q_accept(parser, Q_QUOTE, Q_DO_NOT_ADD_TO_BUFFER)) {
      VALUE str = rb_str_new(parser->buffer, sbcount(parser->buffer));
      q_clear_buf(parser);
      return str;
    } else {
      rb_raise(rb_eRuntimeError, "No closing quote for string");
    }
  }

  return Qnil;
}


static
VALUE
q_read_number(qparser_t *parser)
{
  VALUE result = Qnil;

  if (q_accept_run(parser, Q_DIGITS, Q_ADD_TO_BUFFER)) {
    int is_float = Q_NO;

    if (q_accept(parser, Q_DECIMAL_MARK, Q_ADD_TO_BUFFER)) {
      if (!q_accept_run(parser, Q_DIGITS, Q_ADD_TO_BUFFER)) {
        rb_raise(
          rb_eRuntimeError,
          "Invalid number format: expected fractional value"
          );
        return Qnil;
      }

      is_float = Q_YES;
    }

    if (q_accept(parser, Q_EXPONENT_MARK, Q_ADD_TO_BUFFER)) {
      char plusminus = q_accept(parser, Q_EXP_PLUSMINUS_MARK, Q_ADD_TO_BUFFER);

      if (!q_accept_run(parser, Q_DIGITS, Q_ADD_TO_BUFFER)) {
        rb_raise(rb_eRuntimeError, "Invalid number format: expected exponent");
        return Qnil;
      }

      is_float = is_float || (plusminus == '-');
    }

    sbpush(parser->buffer, '\0');

    if (is_float) {
      result = DBL2NUM(strtod(parser->buffer, NULL));
    } else {
      #ifdef HAVE_LONG_LONG
      result = LL2NUM(strtoll(parser->buffer, NULL, 10));
      #else
      result = LONG2NUM(strtol(parser->buffer, NULL, 10));
      #endif
    }

    q_clear_buf(parser);
  }

  return result;
}


static
ID
q_read_operator(qparser_t *parser)
{
  ID result = 0;

  if (q_accept(parser, Q_NEGATION_MARK, Q_DO_NOT_ADD_TO_BUFFER)) {
    if (!q_accept(parser, Q_EQUAL_MARK, Q_DO_NOT_ADD_TO_BUFFER)) {
      rb_raise(rb_eRuntimeError, "Invalid operator -- expected =");
    }
    result = q_id_not_equal;
  } else if (q_accept(parser, Q_EQUAL_MARK, Q_DO_NOT_ADD_TO_BUFFER)) {
    result = q_id_equal;
  } else if(q_accept(parser, Q_GREATER_MARK, Q_DO_NOT_ADD_TO_BUFFER)) {
    if (q_accept(parser, Q_EQUAL_MARK, Q_DO_NOT_ADD_TO_BUFFER)) {
      result = q_id_greater_equal;
    } else {
      result = q_id_greater;
    }
  } else if(q_accept(parser, Q_LESSER_MARK, Q_DO_NOT_ADD_TO_BUFFER)) {
    if (q_accept(parser, Q_EQUAL_MARK, Q_DO_NOT_ADD_TO_BUFFER)) {
      result = q_id_lesser_equal;
    } else if (q_accept(parser, Q_CONTAINS_MARK, Q_DO_NOT_ADD_TO_BUFFER)) {
      result = q_id_contains;
    } else {
      result = q_id_lesser;
    }
  }

  if (result == 0) {
    rb_raise(rb_eRuntimeError, "Invalid operator -- expected one of "
                               "=, !=, <, <=, >, >=, <-");
    return Qnil;
  }

  return result;
}


static
VALUE
q_read_attribute(qparser_t *parser)
{
  VALUE result = Qnil;

  if (q_accept(parser, Q_START_ATTR, Q_DO_NOT_ADD_TO_BUFFER)) {
    int inverted = Q_NO;
    VALUE key = Qnil;
    ID operator = 0;
    VALUE operand = Qnil;

    q_skip_whitespace(parser);

    inverted = q_accept(parser, Q_NEGATION_MARK, Q_DO_NOT_ADD_TO_BUFFER);
    if (inverted) {
      q_skip_whitespace(parser);
    }

    key = q_read_name(parser, Q_AS_STRING);
    q_skip_whitespace(parser);

    if (q_accept(parser, Q_END_ATTR, Q_DO_NOT_ADD_TO_BUFFER)) {
      operator = q_id_trueish;
      goto skip_operator_operand;
    }

    operator = q_read_operator(parser);
    if (operator == 0) {
      rb_raise(rb_eRuntimeError, "Invalid operator returned");
    }

    q_skip_whitespace(parser);

    operand = q_read_string(parser);
    if (!RTEST(operand)) {
      operand = q_read_number(parser);

      if (!RTEST(operand)) {
        operand = q_read_name(parser, Q_AS_STRING);
      }
    }

    if (NIL_P(operand)) {
      rb_raise(rb_eRuntimeError, "Invalid operand to attribute check");
    }

    q_skip_whitespace(parser);

    if (q_accept(parser, Q_END_ATTR, Q_DO_NOT_ADD_TO_BUFFER)) {
      skip_operator_operand:
      if (inverted) {
        if (operator == q_id_trueish) operator = q_id_falseish;
        else if (operator == q_id_falseish) operator = q_id_trueish;
        else if (operator == q_id_equal) operator = q_id_not_equal;
        else if (operator == q_id_not_equal) operator = q_id_equal;
        else if (operator == q_id_lesser) operator = q_id_greater_equal;
        else if (operator == q_id_greater) operator = q_id_lesser_equal;
        else if (operator == q_id_lesser_equal) operator = q_id_greater;
        else if (operator == q_id_greater_equal) operator = q_id_lesser;
      }

      VALUE args[3] = { key, ID2SYM(operator), operand };
      result = rb_class_new_instance(3, args, q_view_attr_check());
    } else {
      rb_raise(rb_eRuntimeError, "No closing ] for attribute");
    }
  }

  return result;
}


static
VALUE
q_read_multi_class_tag(qparser_t *parser)
{
  if (q_accept(parser, Q_START_MULTI_TAG, Q_DO_NOT_ADD_TO_BUFFER)) {
    VALUE names = rb_ary_new();
    VALUE name = Qnil;

    q_skip_whitespace(parser);

    while (RTEST((name = q_read_name(parser, Q_AS_SYMBOL)))) {
      rb_ary_push(names, name);

      q_skip_whitespace(parser);

      if (!q_accept(parser, Q_MULTI_TAG_SEP, Q_DO_NOT_ADD_TO_BUFFER)) {
        break;
      }
    }

    q_skip_whitespace(parser);

    if (q_accept(parser, Q_END_MULTI_TAG, Q_DO_NOT_ADD_TO_BUFFER)) {
      if (RARRAY_LEN(names) == 0) {
        rb_raise(rb_eRuntimeError, "Cannot have an empty multi-tag selector");
        return Qnil;
      }

      return rb_class_new_instance(1, &names, q_view_class_check());
    } else {
      rb_raise(rb_eRuntimeError, "Unclosed multi-tag selector");
    }
  }
  return Qnil;
}


static
VALUE
q_read_single_class_tag(qparser_t *parser)
{
  VALUE name = q_read_name(parser, Q_AS_SYMBOL);
  if (RTEST(name)) {
    return rb_class_new_instance(1, &name, q_view_class_check());
  }
  return Qnil;
}


static
VALUE
q_read_id_tag(qparser_t *parser)
{
  if (q_accept(parser, Q_TAG_MARKER, Q_DO_NOT_ADD_TO_BUFFER)) {
    VALUE name = q_read_name(parser, Q_AS_SYMBOL);

    if (RTEST(name)) {
      return rb_class_new_instance(1, &name, q_view_tag_check());
    }
  }

  return Qnil;
}


static
VALUE
q_read_selector(qparser_t *parser)
{

  VALUE selector = Qnil;
  VALUE attributes_ary = Qnil;
  VALUE type_check = Qnil;
  int globbed = Q_NO;

  q_skip_whitespace(parser);

  globbed =
    q_accept(parser, Q_ANY_TAG_MARK, Q_DO_NOT_ADD_TO_BUFFER) ||
    q_peek(parser) == '#' ||
    q_peek(parser) == '[';

  if (!globbed) {
    type_check = q_read_multi_class_tag(parser);

    if (NIL_P(type_check)) {
      type_check = q_read_single_class_tag(parser);

      if (NIL_P(type_check)) {
        return Qnil;
      }
    }
  }

  selector = rb_class_new_instance(0, NULL, q_selector_class());
  attributes_ary = q_selector_attributes(selector);

  if (RTEST(type_check)) {
    rb_ary_push(attributes_ary, type_check);
  }

  type_check = q_read_id_tag(parser);
  if (RTEST(type_check)) {
    rb_ary_push(attributes_ary, type_check);
  }

  while (RTEST((type_check = q_read_attribute(parser)))) {
    rb_ary_push(attributes_ary, type_check);
  }

  q_skip_whitespace(parser);

  q_selector_set_direct(
    selector,
    q_accept(parser, Q_DIRECT_FOLLOW, Q_DO_NOT_ADD_TO_BUFFER)
    );

  return selector;
}


static
VALUE
q_rb_ensure_destroy_parser(VALUE parser_data)
{
  qparser_t *parser = (qparser_t *)DATA_PTR(parser_data);
  q_destroy_parser(parser);
  DATA_PTR(parser_data) = NULL;
  return Qnil;
}


static
VALUE
q_rb_run_parser(VALUE parser_data)
{
  qparser_t *parser = (qparser_t *)DATA_PTR(parser_data);
  VALUE selector = Qnil;
  VALUE succ = Qnil;
  VALUE next_succ = Qnil;

  selector = q_read_selector(parser);
  succ = selector;

  if (NIL_P(selector)) {
    rb_raise(rb_eRuntimeError, "Unable to parse selector string");
    return Qnil;
  }

  q_skip_whitespace(parser);

  while (!q_eos(parser) && RTEST(next_succ = q_read_selector(parser))) {
    q_selector_set_succ(succ, next_succ);
    succ = next_succ;
    next_succ = Qnil;
    q_skip_whitespace(parser);
  }

  if (q_eos(parser) && q_selector_is_direct(succ) && NIL_P(q_selector_succ(succ))) {
    rb_raise(rb_eRuntimeError, "No selector following direct reference (>)");
    return Qnil;
  }

  if (!q_eos(parser)) {
    rb_raise(rb_eRuntimeError, "Unable to completely parse selector string");
    return Qnil;
  }

  return selector;
}


static
VALUE
q_rb_parse_selector(VALUE self, VALUE selector_rb_str)
{
  /* selector_rb_str must be UTF8-encoded */
  qparser_t parser;
  const char *sel_cstr = StringValuePtr(selector_rb_str);
  VALUE wrapped_parser = Data_Wrap_Struct(rb_cData, NULL, NULL, &parser);

  /*
    don't use rb_str_length -- just want length in bytes, not necessary valid
    characters
  */
  q_init_parser(&parser, sel_cstr, (int)RSTRING_LEN(selector_rb_str));

  return rb_ensure(
    q_rb_run_parser, wrapped_parser,
    q_rb_ensure_destroy_parser, wrapped_parser
    );
}


void
Init_selector_ext()
{
  /* init ext bindings */
  rb_define_singleton_method(q_parser_module(), "parse", q_rb_parse_selector, 1);

  q_id_equal         = rb_intern("equal");
  q_id_not_equal     = rb_intern("not_equal");
  q_id_greater       = rb_intern("greater");
  q_id_greater_equal = rb_intern("greater_equal");
  q_id_lesser        = rb_intern("lesser");
  q_id_lesser_equal  = rb_intern("lesser_equal");
  q_id_contains      = rb_intern("contains");
  q_id_trueish       = rb_intern("trueish");
  q_id_falseish      = rb_intern("falseish");

  rb_require("gui/selector");
}

