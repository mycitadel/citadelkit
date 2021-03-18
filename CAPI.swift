//
//  CAPI.swift
//  MyCitadelKit
//
//  Created by Maxim Orlovsky on 1/31/21.
//

import os
import Foundation
import Combine

struct ContractJson: Codable {
    let id: String
    let name: String
    let chain: BitcoinNetwork
    let policy: Policy
}

public enum Policy {
    case current(String)
}

extension Policy {
    var descriptor: String {
        switch self {
        case .current(let descriptor): return descriptor
        }
    }
}

extension Policy: Codable {
    enum CodingKeys: CodingKey {
        case current
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.current) {
            let value = try container.decode(String.self, forKey: .current)
            self = .current(value)
        } else {
            throw DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: [CodingKeys.current], debugDescription: "string value expected"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .current(let value):
            try container.encode(value, forKey: .current)
        }
    }
}

struct ContractDataJson: Codable {
    let blindingFactors: [String: OutPoint]
    let sentInvoices: [String]
    let unpaidInvoices: [String: Date]
    let p2cTweaks: [TweakedOutpoint]
}

struct UTXOJson: Codable {
    let height: Int32
    let offset: UInt32
    let txid: String
    let vout: UInt16
    let value: UInt64
    let derivationIndex: UInt32
    let address: String?

    private enum CodingKeys: String, CodingKey {
        case height, offset, txid, vout, value, derivationIndex = "derivation_index", address
    }
}

public struct RGB20Json: Codable {
    public let genesis: String
    public let id: String
    public let ticker: String
    public let name: String
    public let description: String?
    public let decimalPrecision: UInt8
    public let date: String
    public let knownCirculating: UInt64
    public let issueLimit: UInt64?
}

public struct Transfer {
    public let psbt: String
    public let consignment: String?
}

extension CitadelVault {
    public func lastError() -> CitadelError? {
        if citadel_has_err(rpcClient) {
            return CitadelError(errNo: Int(rpcClient.pointee.err_no), message: String(cString: rpcClient.pointee.message))
        } else {
            return nil
        }
    }

    private func processResponseToString(_ response: UnsafePointer<Int8>?) throws -> String {
        guard let response = response else {
            guard let err = lastError() else {
                throw CitadelError("MyCitadel C API is broken")
            }
            throw err
        }
        var string = String(cString: response)
        // TODO: Remove this debug printing
        print(string)
        string.reserveCapacity(string.count * 2)
        release_string(UnsafeMutablePointer(mutating: response))
        return string
    }

    private func processResponse(_ response: UnsafePointer<Int8>?) throws -> Data {
        try Data(processResponseToString(response).utf8)
    }
}

extension WalletContract {
    internal func parseDescriptor() throws -> DescriptorInfo {
        let info = lnpbp_descriptor_parse(policy.descriptor)
        defer {
            result_destroy(info)
        }
        if !is_success(info) {
            let errorMessage = String(cString: info.details.error)
            print("Error parsing address: \(errorMessage)")
            throw CitadelError(errorMessage)
        }
        let jsonString = String(cString: info.details.data)
        let jsonData = Data(jsonString.utf8)
        let decoder = JSONDecoder();
        print("Parsing JSON descriptor data: \(jsonString)")
        do {
            return try decoder.decode(DescriptorInfo.self, from: jsonData)
        } catch {
            print("Error parsing descriptor: \(error.localizedDescription)")
            throw error
        }
    }
}

extension CitadelVault {
    internal func create(singleSig derivation: String, name: String, descriptorType: DescriptorType) throws -> ContractJson {
        print("Creating seed")
        try createSeed()
        let pubkeyChain = try createScopedChain(derivation: derivation)
        let response = citadel_single_sig_create(rpcClient, name, pubkeyChain, descriptorType.cDescriptorType());
        return try JSONDecoder().decode(ContractJson.self, from: processResponse(response))
    }

    internal func listContracts() throws -> [ContractJson] {
        print("Listing contracts")
        let response = citadel_contract_list(rpcClient)
        return try JSONDecoder().decode([ContractJson].self, from: processResponse(response))
    }

    internal func operations(walletId: String) throws -> [TransferOperation] {
        print("Listing operations")
        let response = citadel_contract_operations(rpcClient, walletId)
        return try JSONDecoder().decode([TransferOperation].self, from: processResponse(response))
    }

    internal func balance(walletId: String) throws -> [String: [UTXOJson]] {
        print("Requesting balance for \(walletId)")
        let response = citadel_contract_balance(rpcClient, walletId, true, 20)
        return try JSONDecoder().decode([String: [UTXOJson]].self, from: processResponse(response))
    }

    internal func listAssets() throws -> [RGB20Json] {
        print("Listing assets")
        let response = citadel_asset_list(rpcClient);
        return try JSONDecoder().decode([RGB20Json].self, from: processResponse(response))
    }

    internal func importRGB(genesisBech32 genesis: String) throws -> RGB20Json {
        print("Importing RGB asset")
        let response = citadel_asset_import(rpcClient, genesis);
        return try JSONDecoder().decode(RGB20Json.self, from: processResponse(response))
    }

    public func nextAddress(forContractId contractId: String, useLegacySegWit legacy: Bool = false) throws -> AddressDerivation {
        print("Generating next avaliable address")
        let response = citadel_address_create(rpcClient, contractId, false, legacy)
        return try JSONDecoder().decode(AddressDerivation.self, from: processResponse(response))
    }

    internal func usedAddresses(forContractId contractId: String) throws -> [AddressDerivation] {
        print("Listing used addresses")
        let response = citadel_address_list(rpcClient, contractId, false, 0)
        return try JSONDecoder().decode([String: UInt32].self, from: processResponse(response))
                .map { (address, index) in AddressDerivation(address: address, derivation: [index]) }
    }

    internal func invoice(usingFormat format: InvoiceType, receiveTo contractId: String, nominatedIn assetId: String?, value: UInt64?, from merchant: String? = nil, purpose: String? = nil, useLegacySegWit legacy: Bool = false) throws -> String {
        print("Creating invoice")
        let invoice = citadel_invoice_create(rpcClient, format.cType(), contractId, assetId ?? nil, value ?? 0, merchant ?? nil, purpose ?? nil, false, legacy)
        return try processResponseToString(invoice)
    }

    /*
    public func mark(addressUnused address: String) throws {
        citadel_mark
    }

    public func mark(invoiceUnused invoice: String) throws {
        try vault.mark(invoice: invoice, used: used)
    }
     */

    internal func pay(from contractId: String, invoice: String, value: UInt64? = nil, fee: UInt64, giveaway: UInt64? = nil) throws -> Transfer {
        print("Paying invoice")
        let transfer = citadel_invoice_pay(rpcClient, contractId, invoice, value ?? 0, fee, giveaway ?? 0)
        if !transfer.success {
            guard let err = lastError() else {
                throw CitadelError("MyCitadel C API is broken")
            }
            throw err
        }
        let psbt = String(cString: transfer.psbt_base64)
        release_string(UnsafeMutablePointer(mutating: transfer.psbt_base64))

        let consignment: String?
        if transfer.consignment_bech32 != nil {
            consignment = String(cString: transfer.consignment_bech32)
            release_string(UnsafeMutablePointer(mutating: transfer.consignment_bech32))
        } else {
            consignment = nil
        }

        return Transfer(psbt: psbt, consignment: consignment)
    }

    internal func publish(psbt: String) throws -> String {
        print("Signing and publishing transaction")
        let txid = citadel_psbt_publish(rpcClient, psbt)
        return try processResponseToString(txid)
    }

    internal func accept(consignment: String) throws -> String {
        print("Accepting consignment")
        let status = citadel_invoice_accept(rpcClient, consignment)
        return try processResponseToString(status)
    }
}
