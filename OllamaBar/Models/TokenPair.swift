struct TokenPair: Equatable {
    let prompt: Int
    let eval: Int
    var total: Int { prompt + eval }
}
