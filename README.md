ruby-word97file
===============

Library provides access to MS Word97 file format (read-only)

Why?
====

Because there was nearly no option for ruby considering multi-platform accessing .doc files. 
Win32OLE is bound to win32 platform, and very unreliable when working with large batches of documents. 
Apache TIKA requires java and doesn't provide formfields access, although it works quite good with its ruby binding.
Ruby-docx, besides of neccesity of obvious conversion (eg. doc2x from Dialogika, which requires Win32 .Net support or 32bit(!) Mono on *nix systems), creates large memory overhead from Nokogiri even for simple document...
Any other ? I don't know...

Usage
=====

Rails
-----

Copy given .rb files to ```/lib``` directory, then

```ruby
  require 'ms_doc_file'
  
  doc = MsDocFile.new 'document.doc'
  
  print doc.text
  puts doc.formfields.inspect
  #... and so on ...
```
  
Pure Ruby
---------

Just copy it wherever you want, ```require 'ms_doc_file'```, instantiate MsDocFile class with .doc filename, and voilla!


Code
====

Provided as is, w/o any guarantee and support. Feel free to fork, submit bugs and your thoughts, maybe with your help
it will spawn into something more useful...

Pros?
==================

It works. Sometimes... Rather yes than no...

Cons?
=====

1. Not thoroughly tested, not very optimized
2. Coding style is appaling, ekhm, there's no coding style at all.... it's a Picasso of code...
3. Lib is assuming that fCompressed pieces of document is using ISO-8859-2 encoding, not taking LID (localeID) into account...
4. Code is highly not-documented and not-commented
5. Yes, some parts of code is very similar to doc2x (b2xtranslator of Dialogika), especially considering FormFieldData structures
   Great library in C#, indeed!
6. Gem? Maybe someday, if I'll learn how to create gem & maintain it...

What next?
==========

1. Tables
2. Access to paragraphs
3. Access to character properties (really necessary?)

