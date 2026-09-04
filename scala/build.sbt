// Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
// SPDX-License-Identifier: AGPL-3.0-or-later
// DEED-089: Sovereign Treasury Engine — SBT Build Configuration
// Builds Scala pure pipeline + ZIO effectful pipeline.

name := "devflow-finance-twin-scala"
version := "1.0.0"
scalaVersion := "3.3.1"

libraryDependencies ++= Seq(
  "dev.zio" %% "zio"         % "2.1.1",
  "dev.zio" %% "zio-streams" % "2.1.1"
)

// Compiler options
scalacOptions ++= Seq(
  "-deprecation",
  "-feature",
  "-unchecked",
  "-Xlint:unused"
)

// WORM store output directory
Compile / unmanagedResourceDirectories += baseDirectory.value / "data"
