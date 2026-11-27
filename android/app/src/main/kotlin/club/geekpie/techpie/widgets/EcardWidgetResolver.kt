package club.geekpie.techpie.widgets

data class EcardPresentation(
    val configured: Boolean,
    val showBalance: Boolean,
    val masked: Boolean,
    val displayBalanceText: String,
)

object EcardWidgetResolver {
    fun resolve(
        snapshot: EcardSnapshot?,
        localMaskOverride: Boolean?,
    ): EcardPresentation {
        if (snapshot == null || !snapshot.configured) {
            return EcardPresentation(
                configured = false,
                showBalance = false,
                masked = true,
                displayBalanceText = "",
            )
        }
        val effectiveMasked = localMaskOverride ?: snapshot.hideBalance
        val balance = snapshot.balanceText?.trim()?.takeIf { it.isNotEmpty() }
        if (effectiveMasked || balance == null) {
            return EcardPresentation(
                configured = true,
                showBalance = false,
                masked = effectiveMasked,
                displayBalanceText = if (balance == null) "--" else "••••",
            )
        }
        return EcardPresentation(
            configured = true,
            showBalance = true,
            masked = false,
            displayBalanceText = balance,
        )
    }
}
