---
title: OAuth2 Public Client Flow
summary: Authorization code flow for apps that cannot keep a client secret.
type: conceito
status: seed
origin: agent
created: 2026-06-05
source:
tags: [seguranca, oauth]
aliases: [PKCE, authorization code with PKCE]
---
A single-page or mobile app creates a random verifier, sends only its hash with the authorization request, and proves possession of the verifier when exchanging the code for tokens. This blocks an attacker who steals the authorization code. Store tokens in memory, not local storage.
