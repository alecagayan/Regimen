//
//  SupabaseConfig.swift
//  Regimen
//
//  FILL THESE IN after creating your Supabase project:
//  1. Go to supabase.com, create a project.
//  2. Project Settings -> API -> copy "Project URL" and the "anon public" key.
//  3. Paste them below.
//  4. Run supabase/schema.sql (in the repo root, not the app target) in the
//     Supabase SQL Editor to create the tables, RLS policies, and storage
//     bucket this app expects.
//

import Foundation

enum SupabaseConfig {
    static let url = URL(string: "https://mfsprnlbyolyfcfszpvc.supabase.co")!
    static let anonKey = "sb_publishable_P64ULGej5dh0WOxMmje3sg_zmZGOcwp"
}
