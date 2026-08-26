import Foundation

public extension Build {
    static func resolve(
        _ request: Request
    ) async throws -> Plan {
        guard request.deploy
                || request.selection.requiresResolution else {
            return Plan(
                request: request,
                executableProducts: [],
                executableTargets: [],
                selectedProducts: [],
                perProductDestinations: [:]
            )
        }

        let executableProducts = try await Products.executables(
            in: request.project
        )

        let executableTargets = try await TargetsDetailed.list(
            in: request.project
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

        if plan.request.deploy {
            try Deploy.selected(
                from: plan.request.project,
                config: plan.request.config,
                to: plan.request.destination,
                products: plan.selectedProductNames,
                perProductDestinations: plan.perProductDestinations
            )
        }

        return ExecutionResult(
            plan: plan,
            build: result
        )
    }
}
