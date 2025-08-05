App-Schierer-HPFan
===============================

## INSTALLATION

To install this module type the following:

1. mise install
1. perl Build.PL
1. ./Build installdeps
1. ./Build
1. ./Build install

## DEPENDENCIES

I have attempted to manage tools via cpanm and [mise].
Unless otherwise noted here, you should be able to get
everything necessary between the ```mise install``` and the
```./Build installdeps``` steps.

### Additional Dependencies

* You will need [graphviz], which is used to generate some of the svg files.
* You will need libxml2, which is used to parse the Gramps export.

## COPYRIGHT AND LICENCE

Copyright (C) 2003-2025 by Luke Schierer

Luke's HP Fan Site © 2023-2025 by Luke Schierer is licensed under CC BY-NC 4.0

---

[mise]: https://mise.jdx.dev/
[graphviz]: https://graphviz.org/
