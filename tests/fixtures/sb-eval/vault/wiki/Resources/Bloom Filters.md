---
title: Bloom Filters
summary: A compact probabilistic set: no false negatives, some false positives.
type: conceito
status: draft
origin: human
created: 2026-07-11
source:
tags:
  - estruturas-de-dados
---
A bit array and several hash functions. Adding an element sets its bits; a lookup that finds any bit unset is a definite no, while all bits set means probably yes. Useful in front of an expensive store such as a cache or disk lookup. The false positive rate grows as the filter fills.
