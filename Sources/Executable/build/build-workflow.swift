import Foundation

public extension Build {
    static func resolve(
        _ request: Request
    ) async throws -> Plan {
        guard request.deploy
                || request.selection.requiresResolution
                || request.signing.requiresResolution else {
            return Plan(
                request: request,
                executableProducts: [],
                executableTargets: [],
                selectedProducts: [],
                perProductDestinations: [:]
            )
        }

        let manifest = try await Package.manifest(
            at: request.project
        )

        let executableProducts = try Products.executables(
            in: manifest
        )

        let executableTargets = try TargetsDetailed.list(
            in: manifest
        )

        let targetRoles = Dictionary(
            uniqueKeysWithValues: executableTargets.map {
                ($0.name, $0.role)
            }
        )

        let knownProducts = Set(
            executableProducts.map(\.name)
        )

        let knownTargets = Set(
            executableProducts.flatMap(\.targets)
        )

        let unknownSigningProducts = Set(
            request.signing.products.keys
        )
        .subtracting(knownProducts)
        .sorted()

        guard unknownSigningProducts.isEmpty else {
            throw ResolutionError.unknownSigningProducts(
                unknownSigningProducts
            )
        }

        let unknownProducts = request.selection.products
            .subtracting(knownProducts)
            .sorted()

        guard unknownProducts.isEmpty else {
            throw ResolutionError.unknownProducts(
                unknownProducts
            )
        }

        let unknownTargets = request.selection.legacyTargets
            .subtracting(knownTargets)
            .sorted()

        guard unknownTargets.isEmpty else {
            throw ResolutionError.unknownTargets(
                unknownTargets
            )
        }

        let unknownSkippedProducts = request.selection.skippedProducts
            .subtracting(knownProducts)
            .sorted()

        guard unknownSkippedProducts.isEmpty else {
            throw ResolutionError.unknownSkippedProducts(
                unknownSkippedProducts
            )
        }

        let unknownSkippedTargets = request.selection.legacySkippedTargets
            .subtracting(knownTargets)
            .sorted()

        guard unknownSkippedTargets.isEmpty else {
            throw ResolutionError.unknownSkippedTargets(
                unknownSkippedTargets
            )
        }

        var selectedProducts: [ExecutableProduct]

        if !request.selection.products.isEmpty
            || !request.selection.legacyTargets.isEmpty
        {
            selectedProducts = executableProducts.filter { product in
                request.selection.products.contains(
                    product.name
                )
                    || product.targets.contains { target in
                        request.selection.legacyTargets.contains(
                            target
                        )
                    }
            }
        } else if request.selection.cliOnly {
            selectedProducts = executableProducts.filter { product in
                product.targets.contains { target in
                    targetRoles[target] == .cli
                }
            }
        } else {
            selectedProducts = executableProducts
        }

        if request.selection.keepApps {
            selectedProducts.removeAll { product in
                product.targets.contains { target in
                    targetRoles[target] == .app
                }
            }
        }

        if !request.selection.skippedProducts.isEmpty
            || !request.selection.legacySkippedTargets.isEmpty
        {
            selectedProducts.removeAll { product in
                request.selection.skippedProducts.contains(
                    product.name
                )
                    || product.targets.contains { target in
                        request.selection.legacySkippedTargets.contains(
                            target
                        )
                    }
            }
        }

        var perProductDestinations: [String: URL] = [:]

        for product in executableProducts {
            if let destination = request.selection.destinationMappings[
                product.name
            ] {
                perProductDestinations[product.name] = destination
                continue
            }

            for target in product.targets {
                guard let destination = request.selection.destinationMappings[
                    target
                ] else {
                    continue
                }

                perProductDestinations[product.name] = destination
                break
            }
        }

        return Plan(
            request: request,
            executableProducts: executableProducts,
            executableTargets: executableTargets,
            selectedProducts: selectedProducts,
            perProductDestinations: perProductDestinations
        )
    }

    static func execute(
        _ plan: Plan,
        captureOutput: Bool = false
    ) async throws -> ExecutionResult {
        let result: BuildResult

        if captureOutput {
            result = try await captured(
                at: plan.request.project,
                config: plan.request.config,
                argv_audit: plan.request.source.arguments
            )
        } else {
            result = try await build(
                at: plan.request.project,
                config: plan.request.config,
                argv_audit: plan.request.source.arguments
            )
        }

        var sourceSignings: [(
            product: String,
            result: CodeSigning.SignResult
        )] = []

        for product in plan.selectedProducts {
            guard let configuration = plan.request.signing.configuration(
                for: product.name
            ) else {
                continue
            }

            let signer = try await CodeSigning.resolve(
                configuration.identity
            )
            let target = plan.request.project
                .standardizedFileURL
                .appendingPathComponent(
                    ".build",
                    isDirectory: true
                )
                .appendingPathComponent(
                    plan.request.config.buildDirComponent,
                    isDirectory: true
                )
                .appendingPathComponent(
                    product.name,
                    isDirectory: false
                )

            let signing = try await CodeSigning.sign(
                .init(
                    target: target,
                    signer: signer,
                    identifier: configuration.identifier,
                    entitlements: configuration.entitlements,
                    hardenedRuntime: configuration.hardenedRuntime
                )
            )

            sourceSignings.append(
                (
                    product: product.name,
                    result: signing
                )
            )
        }

        if plan.request.deploy {
            try Deploy.selected(
                from: plan.request.project,
                config: plan.request.config,
                to: plan.request.destination,
                products: plan.selectedProductNames,
                perProductDestinations: plan.perProductDestinations
            )
        }

        var signingResults: [ProductSigningResult] = []

        for signing in sourceSignings {
            guard plan.request.deploy else {
                signingResults.append(
                    .init(
                        product: signing.product,
                        source: signing.result,
                        deployedVerification: nil,
                        deployedInspection: nil
                    )
                )
                continue
            }

            let destinationRoot = plan.perProductDestinations[
                signing.product
            ] ?? plan.request.destination
            let deployedTarget = destinationRoot
                .appendingPathComponent(
                    signing.product,
                    isDirectory: false
                )
            let verification = try await CodeSigning.verify(
                deployedTarget
            )

            guard verification.valid else {
                throw SigningError.deployedSignatureInvalid(
                    product: signing.product,
                    target: deployedTarget,
                    output: verification.output
                )
            }

            signingResults.append(
                .init(
                    product: signing.product,
                    source: signing.result,
                    deployedVerification: verification,
                    deployedInspection: try await CodeSigning.inspect(
                        deployedTarget
                    )
                )
            )
        }

        return ExecutionResult(
            plan: plan,
            build: result,
            signing: signingResults
        )
    }
}
