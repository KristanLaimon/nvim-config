; extends

; Livewire 3 @script directive
((livewire
  (directive_start) @_start
  (text) @injection.content)
  (#lua-match? @_start "^@script")
  (#set! injection.language "javascript"))

; Livewire 3 @assets directive
((livewire
  (directive_start) @_start
  (text) @injection.content)
  (#lua-match? @_start "^@assets")
  (#set! injection.language "html"))

; TypeScript script block: <script lang="ts"> or <script lang="typescript">
((script_element
  (start_tag
    (attribute
      (attribute_name) @_attr
      (#eq? @_attr "lang")
      (quoted_attribute_value
        (attribute_value) @_lang)))
  (raw_text) @injection.content)
  (#any-of? @_lang "ts" "typescript")
  (#set! injection.language "typescript"))

; Explicit SCSS style block: <style lang="scss"> or <style type="text/scss">
((style_element
  (start_tag
    (attribute
      (attribute_name) @_attr
      (quoted_attribute_value
        (attribute_value) @_val)))
  (raw_text) @injection.content)
  (#any-of? @_attr "lang" "type")
  (#any-of? @_val "scss" "text/scss")
  (#set! injection.language "scss"))

; Explicit SCSS syntax inside <style> ($variables, @mixin, @include, @extend, @use, @forward)
((style_element
  (start_tag) @_tag
  (raw_text) @injection.content)
  (#not-lua-match? @_tag "%slang%s*=")
  (#not-lua-match? @_tag "%stype%s*=")
  (#lua-match? @injection.content "(%$(%w|_-)+%s*:|@mixin%s+|@include%s+|@extend%s+|@use%s+|@forward%s+)")
  (#set! injection.language "scss"))
