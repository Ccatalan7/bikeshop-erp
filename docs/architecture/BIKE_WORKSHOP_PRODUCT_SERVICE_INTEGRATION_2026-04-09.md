# Bike Workshop Product and Service Integration - 2026-04-09

## Handoff Signatures

- Architecture correction and integration rules: GPT-5.4
- Future implementation target: Gemini 3.1 Pro

## Purpose

This document makes one rule explicit:

The bike memory model must be built on the same bike/job/item/product/service backbone that already exists in the business workflow.

## Existing linkage already present in code

The repo already has the correct operational seam:

- `mechanic_job_bikes` links a job to a specific serviced bike
- `mechanic_job_items.job_bike_id` links an item to that specific serviced bike
- `mechanic_job_items.product_id` links installed parts to real products
- `mechanic_job_items.service_product_id` links performed service flows to real service products

This means parts and services are already structurally close to bike tracking.

Future implementation must build on this seam instead of bypassing it.

## Shared authoritative identities

### Real parts

Use `products` as the authoritative identity for installable tracked parts whenever possible.

Examples:

- chain
- rotor
- brake pads
- tire

### Real services

Use service products as the authoritative identity for performed service workflows.

Examples:

- brake bleed
- pad replacement
- rotor installation
- drivetrain service

### Technical meaning

Use the product ficha tecnica system as the authoritative technical meaning of the installed part.

Use service profiles as the authoritative workflow meaning of the performed service.

### Bike encyclopedia

Use the bike encyclopedia as a suggestion/reference layer that follows the same technical concepts.

It must not introduce a separate incompatible schema philosophy.

## Core rule

Tracked bike components should be the same products the shop installs, and tracked service actions should be the same service products the shop bills.

If the implementation drifts away from that rule, it is recreating the same fragmentation problem the whole initiative is meant to eliminate.