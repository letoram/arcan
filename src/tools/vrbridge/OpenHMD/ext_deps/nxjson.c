/*
 * nxjson
 * Copyright 2018 Yaroslav Stavnichiy <yarosla@gmail.com>
 * SPDX-License-Identifier: MIT
 * Explicit permission to use this project
 * under the MIT license has been given by Yaroslav Stavnichiy
 * on Sun, May 20, 2018 at 1:29 PM (CET). Original license is LGPL v3
 */
// this file can be #included in your code
#ifndef NXJSON_C
#define NXJSON_C

#ifdef  __cplusplus
extern "C" {
#endif


#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <errno.h>

#include "nxjson.h"

// redefine NX_JSON_CALLOC & NX_JSON_FREE to use custom allocator
#ifndef NX_JSON_CALLOC
#define NX_JSON_CALLOC() calloc(1, sizeof(nx_json))
#define NX_JSON_FREE(json) free((void*)(json))
#endif

// redefine NX_JSON_REPORT_ERROR to use custom error reporting
#ifndef NX_JSON_REPORT_ERROR
#define NX_JSON_REPORT_ERROR(msg, p) fprintf(stderr, "NXJSON PARSE ERROR (%d): " msg " at %s\n", __LINE__, p)
#endif

#define IS_WHITESPACE(c) ((unsigned char)(c)<=(unsigned char)' ')

static const nx_json dummy={ NX_JSON_NULL };

static nx_json* create_json(nx_json_type type, const char* key, nx_json* parent) {
  nx_json* js=NX_JSON_CALLOC();
  assert(js);
  js->type=type;
  js->key=key;
  js->parent=parent;
  if (!parent->last_child) {
    parent->child=parent->last_child=js;
  }
  else {
    parent->last_child->next=js;
    parent->last_child=js;
  }
  parent->length++;
  return js;
}

void nx_json_free(const nx_json* js) {
  nx_json* p=js->child;
  nx_json* p1;
  while (p) {
    p1=p->next;
    nx_json_free(p);
    p=p1;
  }
  NX_JSON_FREE(js);
}

static int unicode_to_utf8(unsigned int codepoint, char* p, char** endp) {
  // code from http://stackoverflow.com/a/4609989/697313
  if (codepoint<0x80) *p++=codepoint;
  else if (codepoint<0x800) *p++=192+codepoint/64, *p++=128+codepoint%64;
  else if (codepoint-0xd800u<0x800) return 0; // surrogate must have been treated earlier
  else if (codepoint<0x10000) *p++=224+codepoint/4096, *p++=128+codepoint/64%64, *p++=128+codepoint%64;
  else if (codepoint<0x110000) *p++=240+codepoint/262144, *p++=128+codepoint/4096%64, *p++=128+codepoint/64%64, *p++=128+codepoint%64;
  else return 0; // error
  *endp=p;
  return 1;
}

nx_json_unicode_encoder nx_json_unicode_to_utf8=unicode_to_utf8;

static inline int hex_val(char c) {
  if (c>='0' && c<='9') return c-'0';
  if (c>='a' && c<='f') return c-'a'+10;
  if (c>='A' && c<='F') return c-'A'+10;
  return -1;
}

static char* unescape_string(char* s, char** end, nx_json_unicode_encoder encoder) {
  char* p=s;
  char* d=s;
  char c;
  while ((c=*p++)) {
    if (c=='"') {
      *d='\0';
      *end=p;
      return s;
    }
    else if (c=='\\') {
      switch (*p) {
        case '\\':
        case '/':
        case '"':
          *d++=*p++;
          break;
        case 'b':
          *d++='\b'; p++;
          break;
        case 'f':
          *d++='\f'; p++;
          break;
        case 'n':
          *d++='\n'; p++;
          break;
        case 'r':
          *d++='\r'; p++;
          break;
        case 't':
          *d++='\t'; p++;
          break;
        case 'u': // unicode
          if (!encoder) {
            // leave untouched
            *d++=c;
            break;
          }
          char* ps=p-1;
          int h1, h2, h3, h4;
          if ((h1=hex_val(p[1]))<0 || (h2=hex_val(p[2]))<0 || (h3=hex_val(p[3]))<0 || (h4=hex_val(p[4]))<0) {
            NX_JSON_REPORT_ERROR("invalid unicode escape", p-1);
            return 0;
          }
          unsigned int codepoint=h1<<12|h2<<8|h3<<4|h4;
          if ((codepoint & 0xfc00)==0xd800) { // high surrogate; need one more unicode to succeed
            p+=6;
            if (p[-1]!='\\' || *p!='u' || (h1=hex_val(p[1]))<0 || (h2=hex_val(p[2]))<0 || (h3=hex_val(p[3]))<0 || (h4=hex_val(p[4]))<0) {
              NX_JSON_REPORT_ERROR("invalid unicode surrogate", ps);
              return 0;
            }
            unsigned int codepoint2=h1<<12|h2<<8|h3<<4|h4;
            if ((codepoint2 & 0xfc00)!=0xdc00) {
              NX_JSON_REPORT_ERROR("invalid unicode surrogate", ps);
              return 0;
            }
            codepoint=0x10000+((codepoint-0xd800)<<10)+(codepoint2-0xdc00);
          }
          if (!encoder(codepoint, d, &d)) {
            NX_JSON_REPORT_ERROR("invalid codepoint", ps);
            return 0;
          }
          p+=5;
          break;
        default:
          // leave untouched
          *d++=c;
          break;
      }
    }
    else {
      *d++=c;
    }
  }
  NX_JSON_REPORT_ERROR("no closing quote for string", s);
  return 0;
}

static char* skip_block_comment(char* p) {
  // assume p[-2]=='/' && p[-1]=='*'
  char* ps=p-2;
  if (!*p) {
    NX_JSON_REPORT_ERROR("endless comment", ps);
    return 0;
  }
  REPEAT:
  p=strchr(p+1, '/');
  if (!p) {
    NX_JSON_REPORT_ERROR("endless comment", ps);
    return 0;
  }
  if (p[-1]!='*') goto REPEAT;
  return p+1;
}

static char* parse_key(const char** key, char* p, nx_json_unicode_encoder encoder) {
  // on '}' return with *p=='}'
  char c;
  while ((c=*p++)) {
    if (c=='"') {
      *key=unescape_string(p, &p, encoder);
      if (!*key) return 0; // propagate error
      while (*p && IS_WHITESPACE(*p)) p++;
      if (*p==':') return p+1;
      NX_JSON_REPORT_ERROR("unexpected chars", p);
      return 0;
    }
    else if (IS_WHITESPACE(c) || c==',') {
      // continue
    }
    else if (c=='}') {
      return p-1;
    }
    else if (c=='/') {
      if (*p=='/') { // line comment
        char* ps=p-1;
        p=strchr(p+1, '\n');
        if (!p) {
          NX_JSON_REPORT_ERROR("endless comment", ps);
          return 0; // error
        }
        p++;
      }
      else if (*p=='*') { // block comment
        p=skip_block_comment(p+1);
        if (!p) return 0;
      }
      else {
        NX_JSON_REPORT_ERROR("unexpected chars", p-1);
        return 0; // error
      }
    }
    else {
      NX_JSON_REPORT_ERROR("unexpected chars", p-1);
      return 0; // error
    }
  }
  NX_JSON_REPORT_ERROR("unexpected chars", p-1);
  return 0; // error
}

static char* parse_value(nx_json* parent, const char* key, char* p, nx_json_unicode_encoder encoder) {
  nx_json* js;
  while (1) {
    switch (*p) {
      case '\0':
        NX_JSON_REPORT_ERROR("unexpected end of text", p);
        return 0; // error
      case ' ': case '\t': case '\n': case '\r':
      case ',':
        // skip
        p++;
        break;
      case '{':
        js=create_json(NX_JSON_OBJECT, key, parent);
        p++;
        while (1) {
          const char* new_key;
          p=parse_key(&new_key, p, encoder);
          if (!p) return 0; // error
          if (*p=='}') return p+1; // end of object
          p=parse_value(js, new_key, p, encoder);
          if (!p) return 0; // error
        }
      case '[':
        js=create_json(NX_JSON_ARRAY, key, parent);
        p++;
        while (1) {
          p=parse_value(js, 0, p, encoder);
          if (!p) return 0; // error
          if (*p==']') return p+1; // end of array
        }
      case ']':
        return p;
      case '"':
        p++;
        js=create_json(NX_JSON_STRING, key, parent);
        js->text_value=unescape_string(p, &p, encoder);
        if (!js->text_value) return 0; // propagate error
        return p;
      case '-': case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7': case '8': case '9':
        {
          js=create_json(NX_JSON_INTEGER, key, parent);
          char* pe;
          js->int_value=strtoll(p, &pe, 0);
          if (pe==p || errno==ERANGE) {
            NX_JSON_REPORT_ERROR("invalid number", p);
            return 0; // error
          }
          if (*pe=='.' || *pe=='e' || *pe=='E') { // double value
            js->type=NX_JSON_DOUBLE;
            js->dbl_value=strtod(p, &pe);
            if (pe==p || errno==ERANGE) {
              NX_JSON_REPORT_ERROR("invalid number", p);
              return 0; // error
            }
          }
          else {
            js->dbl_value=js->int_value;
          }
          return pe;
        }
      case 't':
        if (!strncmp(p, "true", 4)) {
          js=create_json(NX_JSON_BOOL, key, parent);
          js->int_value=1;
          return p+4;
        }
        NX_JSON_REPORT_ERROR("unexpected chars", p);
        return 0; // error
      case 'f':
        if (!strncmp(p, "false", 5)) {
          js=create_json(NX_JSON_BOOL, key, parent);
          js->int_value=0;
          return p+5;
        }
        NX_JSON_REPORT_ERROR("unexpected chars", p);
        return 0; // error
      case 'n':
        if (!strncmp(p, "null", 4)) {
          create_json(NX_JSON_NULL, key, parent);
          return p+4;
        }
        NX_JSON_REPORT_ERROR("unexpected chars", p);
        return 0; // error
      case '/': // comment
        if (p[1]=='/') { // line comment
          char* ps=p;
          p=strchr(p+2, '\n');
          if (!p) {
            NX_JSON_REPORT_ERROR("endless comment", ps);
            return 0; // error
          }
          p++;
        }
        else if (p[1]=='*') { // block comment
          p=skip_block_comment(p+2);
          if (!p) return 0;
        }
        else {
          NX_JSON_REPORT_ERROR("unexpected chars", p);
          return 0; // error
        }
        break;
      default:
        NX_JSON_REPORT_ERROR("unexpected chars", p);
        return 0; // error
    }
  }
}

const nx_json* nx_json_parse_utf8(char* text) {
  return nx_json_parse(text, unicode_to_utf8);
}

const nx_json* nx_json_parse(char* text, nx_json_unicode_encoder encoder) {
  nx_json js={0};
  if (!parse_value(&js, 0, text, encoder)) {
    if (js.child) nx_json_free(js.child);
    return 0;
  }
  return js.child;
}

const nx_json* nx_json_get(const nx_json* json, const char* key) {
  if (!json || !key) return &dummy; // never return null
  nx_json* js;
  for (js=json->child; js; js=js->next) {
    if (js->key && !strcmp(js->key, key)) return js;
  }
  return &dummy; // never return null
}

const nx_json* nx_json_item(const nx_json* json, int idx) {
  if (!json) return &dummy; // never return null
  nx_json* js;
  for (js=json->child; js; js=js->next) {
    if (!idx--) return js;
  }
  return &dummy; // never return null
}


#ifdef  __cplusplus
}
#endif

#endif  /* NXJSON_C */
