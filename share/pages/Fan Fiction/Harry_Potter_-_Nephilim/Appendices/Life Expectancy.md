---
title: >-
  Life Expectancy
author: Luke Schierer
collection: Nephilim
order: 100
---

| Average Power Level | US Males 1900 | US Males 2001 | US Male Nephilim 1900 |
| :-----------------: | :-----------: | :-----------: | :-------------------: |
|          0          |     51.5      |     77.8      |         51.5          |
|          1          |     51.5      |     77.8      |         57.50         |
|          2          |     51.5      |     77.8      |         64.71         |
|          3          |     51.5      |     77.8      |         73.37         |
|          4          |     51.5      |     77.8      |         83.77         |
|          5          |     51.5      |     77.8      |         96.25         |
|          6          |     51.5      |     77.8      |        111.24         |
|          7          |     51.5      |     77.8      |        129.25         |
|          8          |     51.5      |     77.8      |        150.86         |
|          9          |     51.5      |     77.8      |        176.82         |
|         10          |     51.5      |     77.8      |        207.99         |

| Average Power Level | US Females 1900 | US Females 2001 | US Female Nephilim 1900 |
| :-----------------: | :-------------: | :-------------: | :---------------------: |
|          0          |      58.3       |      82.8       |          58.3           |
|          1          |      58.3       |      82.8       |          63.39          |
|          2          |      58.3       |      82.8       |          69.65          |
|          3          |      58.3       |      82.8       |          77.32          |
|          4          |      58.3       |      82.8       |          86.75          |
|          5          |      58.3       |      82.8       |          98.31          |
|          6          |      58.3       |      82.8       |         112.51          |
|          7          |      58.3       |      82.8       |         129.94          |
|          8          |      58.3       |      82.8       |         151.33          |
|          9          |      58.3       |      82.8       |         177.60          |
|         10          |      58.3       |      82.8       |         209.83          |

The above table is in part based on Ms. Felicitie C. Bell, Mr. Michael L. Miller. "[Life Tables for the United States Social Security Area 1900-2100]" 2005-08. SSA Pub. No. 11-11536.

I'm using 1900's US numbers essentially because 1) I do not have UK numbers 2)
1900's numbers seams to me a reasonable average between the effects of the magic
that nephil would use (cooling charms, preservation charms, medical charms and
potions), versus their tendency to ignore non-magical advances in science after
the statute of secrecy.

The extend to which magic extends the nephil's life depends on the nephil's
average power level. For males, I settled on the formula

```
a = x-29.9+29.9e^0.183y
```

where a is their estimated average lifespan, x is the life expectancy for a
non-magical person, e is Euler's number, and y is the average of their nine
power levels (excluding any zeros). For females, using the same variables,
I settled on the formula

```
a = x-22.39+22.39e^0.205y
```

I chose the different formulas because while it does not fully remove the fact
that women normally live longer than men, it does massively reduce the delta.
I decided (while I have no proof of this) a large part of the difference between
male and female humans has got to be either the effects of more guys involved
in wars or disease (or both).

Looking at the above, Euphemia should have had a life expectancy of around 130
years and Fleamont of around 111 years, yet they had James at around 68 and died
at around 87. The first says that magic is extending fertility as well as
lifespan. The second says that these are _average_ numbers, and that there are
still magical diseases that can drastically shorten them (since we know they
died of dragon pox).

The other interesting thing about this table is the implications of the magical world
ignoring modern medical advances. You can see that the mundane world has already
wiped out the difference in lifespan for first few power ranks, and in fact live
_longer_ than rank one, two, or three powered nephilim do supposing such nephilim
remain in the magical world. This is something to keep in mind when the books describe
so many characters as appearing old. People _did_ age faster in earlier centuries,
due to hardship, poor diet, disease, and a variety of other causes. While the magical
world may have eliminated much of the mundane disease, the impression is that the
other problems remain prevelant.

This gives our central characters life expectancies as follows:

|     Last Name     | First Name | Average Power | Life Expectancy |
| :---------------: | :--------: | :-----------: | :-------------: |
|    Dumbledore     |   Albus    |     8.22      |     155.85      |
|      Riddle       |    Tom     |     8.00      |     150.76      |
|      Potter       |   Harry    |     8.00      |     150.76      |
|       Snape       |  Severus   |     7.55      |     140.30      |
|      Abbott       |   Hannah   |     5.77      |     108.90      |
|       Bones       |   Susan    |     6.77      |     125.47      |
|      Granger      |  Hermione  |     6.22      |     115.84      |
|      Weasley      |    Fred    |     7.00      |     129.24      |
|      Weasley      |   George   |     7.00      |     129.24      |
|      Weasley      |  Charlie   |     7.00      |     129.24      |
|      Weasley      |    Bill    |     7.22      |     133.42      |
|      Weasley      |   Ronald   |     6.22      |     114.88      |
|      Weasley      |   Percy    |     6.11      |     112.79      |
|      Weasley      |   Ginny    |     7.55      |     140.91      |
|      Weasley      |   Arthur   |     7.33      |     135.81      |
| Weasley (Prewett) |   Molly    |     6.88      |     127.48      |
|     Delacour      |   Fleur    |     7.44      |    111.29\*     |

\* Fleur is quarter-veela, see [The Veela Curse].

[The Veela Curse]: <./Veela Pathology>
[Life Tables for the United States Social Security Area 1900-2100]: https://www.ssa.gov/oact/NOTES/pdf_studies/study120.pdf
