## onboarding_service-v0.24.0 (2026-05-10)

### fix

- add server_default to stats columns to allow migration of existing users

## onboarding_service-v0.23.0 (2026-05-10)

### chore

- remove empty migration file 71cd58472fda

## onboarding_service-v0.22.0 (2026-05-09)

### feat

- add is_public parameter to upload_file_to_s3 to support configurable bucket ACLs

## onboarding_service-v0.21.0 (2026-05-09)

### feat

- add S3 file deletion logic and improve Ansible secret management persistence

## onboarding_service-v0.20.1 (2026-05-09)

### fix

- update S3 client configuration to use path-style addressing

## onboarding_service-v0.20.0 (2026-05-09)

### feat

- configure s3v4 signature version for s3 client connections

## onboarding_service-v0.19.1 (2026-05-09)

### fix

- update S3_BUCKET_NAME to use hyphenated naming convention

## onboarding_service-v0.19.0 (2026-05-09)

### feat

- add tenacity retry logic to S3 file uploads with seek support

## onboarding_service-v0.18.0 (2026-05-09)

### feat

- add 5MB file size validation and RabbitMQ profile update notification to onboarding endpoint

## onboarding_service-v0.17.2 (2026-05-09)

### chore

- update S3_BUCKET_NAME to use underscore naming convention

## onboarding_service-v0.17.1 (2026-05-09)

### chore

- regenerate migration to add profile_photo_url and remove driver_details columns

## onboarding_service-v0.17.0 (2026-05-09)

### feat

- implement ride booking infrastructure, app-link support, and robust auth token handling

## onboarding_service-v0.16.0 (2026-05-05)

### feat

- include email_verified field in user profile API response

## onboarding_service-v0.15.1 (2026-04-07)

### refactor

- remove redundant timestamp fields from API response schemas

## onboarding_service-v0.15.0 (2026-04-07)

### feat

- - refactor role system to support dual Rider/Driver assignments simultaneously - implement deferred Driver privilege (is_driver = True only after vehicle verification) - add 'role_intent' tracking to maintain user signup context - add automated UTC timestamps (created_at, updated_at) to all onboarding models

## onboarding_service-v0.14.0 (2026-04-07)

### feat

- add location_enabled and details_confirmed flags to user profiles and onboarding flow

## onboarding_service-v0.13.2 (2026-04-07)

### refactor

- remove redis retry strategy from onboarding service connection initialization

## onboarding_service-v0.13.1 (2026-04-07)

### fix

- disconnect redis connection pool before retrying failed operations in otp service

## onboarding_service-v0.13.0 (2026-04-07)

### feat

- add retry logic with exponential backoff for Redis operations in OTP service

## onboarding_service-v0.12.0 (2026-04-07)

### feat

- implement exponential backoff retry strategy for Redis connection

## onboarding_service-v0.11.0 (2026-04-07)

### feat

- add health checks and retry logic to Redis connection initialization

## onboarding_service-v0.10.0 (2026-04-07)

### feat

- implement resilient RabbitMQ connection handling with startup softening and automatic publish retries

## onboarding_service-v0.9.0 (2026-04-06)

### feat

- enhance onboarding and payment services with new API tokens and database operations

## onboarding_service-v0.8.1 (2026-04-05)

### fix

- add email OTP verification and resend OTP endpoints

## onboarding_service-v0.8.0 (2026-04-05)

### feat

- add hiredis, pyjwt, and redis packages with respective versions
- update email template and sender for OTP verification

## onboarding_service-v0.7.0 (2026-04-04)

### feat

- add endpoints to update and delete user profiles and driver details

### fix

- update S3 region name to 'eu-central'

## onboarding_service-v0.6.2 (2026-04-04)

### refactor

- update migration scripts for car colour and national ID photo

## onboarding_service-v0.6.1 (2026-04-04)

### refactor

- enhance build and push targets for multi-platform support

## onboarding_service-v0.6.0 (2026-04-04)

### feat

- add car_colour and national_id_photo_url fields to DriverDetails model and migration

## onboarding_service-v0.5.0 (2026-04-04)

### feat

- enhance onboarding service with new migration command and update database schema

## onboarding_service-v0.4.0 (2026-04-04)

### feat

- implement onboarding service database migrations with retry logic and locking

## onboarding_service-v0.3.1 (2026-04-04)

## onboarding_service-v0.3.0 (2026-04-04)

## onboarding_service-v0.2.0 (2026-04-04)

- Changelog reset to establish service-only history.
