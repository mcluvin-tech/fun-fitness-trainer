#!/usr/bin/env bash
# Opens Supabase + Google Cloud pages for Gmail sign-in setup.
set -euo pipefail

PROJECT_REF="${SUPABASE_PROJECT_REF:-oidzizeeveglgqsmowaz}"

echo "Gmail sign-in setup for Fun Fitness Trainer"
echo "Project ref: $PROJECT_REF"
echo ""
echo "Checklist:"
echo "  1. Google Cloud → OAuth Web client"
echo "     Redirect URI: https://${PROJECT_REF}.supabase.co/auth/v1/callback"
echo "  2. Supabase → Authentication → Providers → Google (enable + paste ID/secret)"
echo "  3. Supabase → URL Configuration → add funfitnesstrainer://auth-callback"
echo ""
echo "Full guide: docs/GOOGLE_SIGNIN.md"
echo ""

open "https://console.cloud.google.com/apis/credentials" 2>/dev/null || true
open "https://supabase.com/dashboard/project/${PROJECT_REF}/auth/providers?provider=Google" 2>/dev/null || true
open "https://supabase.com/dashboard/project/${PROJECT_REF}/auth/url-configuration" 2>/dev/null || true

echo "Opened Google Cloud Credentials and Supabase auth pages in your browser."
