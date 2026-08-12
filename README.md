# Luggage Storage Booking Platform

A Flutter-based mobile application prototype for a luggage storage booking platform, developed as part of an early-stage startup project.

The platform allows users to find partner locations where they can safely store their luggage, create bookings, manage reservations, and interact with partner businesses through a structured booking flow.

> **Disclaimer:** This repository contains an early prototype developed for portfolio and academic purposes. It is not affiliated with, endorsed by, or representative of any currently active commercial product, company, or brand.

## Overview

This project implements a mobile-first luggage storage booking platform using **Flutter** and **Supabase**.

The application includes user authentication, role-based access, partner onboarding, interactive maps, dynamic booking management, luggage capacity calculation, and admin/partner workflows.

The goal of the project was to design and implement a real-world booking system involving multiple user roles, database-backed logic, and mobile user experience.

## Main Features

### User Features

Users can:

- register and log in using email and password;
- verify their account through OTP;
- view partner locations on an interactive map;
- open partner detail pages with information such as description, rules, prices, opening hours, and location;
- create luggage storage bookings through a guided multi-step flow;
- select drop-off and pick-up date/time;
- specify luggage quantities by size;
- view and manage personal bookings;
- cancel active bookings when allowed;
- manage their profile information;
- request account deletion.

### Partner Features

Partners can:

- access a dedicated partner workflow;
- manage business information;
- configure opening hours and exceptional closures/openings;
- manage luggage capacity settings;
- view received bookings;
- update booking status;
- temporarily enable or disable booking availability;
- manage their location visibility and operational details.

### Admin / Approval Workflow

The platform includes a structured onboarding and approval flow for partner businesses.

The workflow supports:

- partner registration through a web-based onboarding process;
- partner request statuses such as draft, submitted, awaiting payment, paid, and rejected;
- admin-side review and approval logic;
- role transitions between standard users, partner candidates, and approved partners.

## Booking and Capacity Logic

The application includes a dynamic luggage capacity system.

Luggage sizes are modeled using equivalent capacity units:

- **1 small luggage** = 1 unit
- **1 medium luggage** = 2 units
- **1 large luggage** = 4 units

The booking flow checks availability over a selected time interval by considering:

- partner base capacity;
- extra dedicated capacity by luggage size;
- accepted luggage sizes;
- overlapping active bookings;
- total occupied capacity during the requested interval.

This allows the system to estimate whether a partner can accept a new booking based on both luggage size and available space.

## Tech Stack

- **Mobile:** Flutter, Dart
- **Backend as a Service:** Supabase
- **Database:** PostgreSQL
- **Authentication:** Supabase Auth
- **Storage:** Supabase Storage
- **Backend Logic:** Supabase RPC functions and database policies
- **Maps:** Interactive map integration
- **Development Tools:** Git, VS Code

## Project Structure

```text
luggage-storage-booking-platform/
├── app/
│   └── Flutter mobile application
├── supabase/
│   └── Database migrations, SQL functions, and backend logic
├── partner-onboarding-site/
│   └── Web-based partner onboarding flow
├── README.md
└── ...
```

> The exact structure may vary depending on the local version of the project.

## Academic / Project Context

This project was developed as part of an early-stage startup idea involving a luggage storage booking service.

My contribution focused on the software prototype, application flows, database-backed logic, user experience, and integration between the mobile app and the Supabase backend.

The repository represents an early prototype and does not represent the current version of any active commercial application.

## What I Learned

Through this project, I practiced:

- building mobile applications with Flutter;
- designing multi-role user flows;
- integrating a mobile app with Supabase;
- working with authentication and OTP flows;
- modeling booking and reservation systems;
- designing database-backed application logic;
- handling role-based access and user states;
- implementing partner onboarding workflows;
- managing dynamic capacity and availability logic;
- structuring a real-world product prototype.

## Limitations

This repository is an early-stage prototype and may not include all production-level features.

Known limitations include:

- no production payment system;
- limited production hardening;
- prototype-level UI and UX in some areas;
- incomplete commercial deployment setup;
- no guarantee that all flows match a currently active product.

## Disclaimer

This project is a portfolio prototype inspired by luggage storage booking services.

It is not affiliated with, endorsed by, or representative of any currently active commercial product, company, or brand.
