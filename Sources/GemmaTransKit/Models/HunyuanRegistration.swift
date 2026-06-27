//
//  HunyuanRegistration.swift
//  GemmaTransKit
//
//  把混元 dense 架构（HunyuanModel）注册进 LLMTypeRegistry.shared。
//  loadModelContainer(from:using:) → ModelFactoryRegistry → LLMModelFactory.shared
//  按 config.json 的 model_type 经此 registry 分发，故注册后现有加载路径即可加载 Hy-MT2。
//

import Foundation
import MLXLLM
import MLXLMCommon

private actor HunyuanRegistrationState {
    static let shared = HunyuanRegistrationState()
    private(set) var registered = false
    func mark() { registered = true }
}

/// 幂等注册混元类型（registerModelType 本是字典赋值，重复调用亦无害；此处再加 actor 闸避免无谓 await）。
public func registerHunyuanIfNeeded() async {
    if await HunyuanRegistrationState.shared.registered { return }
    await LLMTypeRegistry.shared.registerModelType("hunyuan_v1_dense") { data in
        let config = try JSONDecoder().decode(HunyuanConfiguration.self, from: data)
        return HunyuanModel(config)
    }
    await HunyuanRegistrationState.shared.mark()
}
