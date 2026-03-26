// SPDX-License-Identifier: MIT
//
// main.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Command-line entry point that delegates to the shared runner.
//

import Foundation
import TransformationSwiftUI

let exitCode = TransformationSwiftUIRunner.run(arguments: CommandLine.arguments)
exit(Int32(exitCode))
