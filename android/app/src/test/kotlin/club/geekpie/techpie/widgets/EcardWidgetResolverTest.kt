package club.geekpie.techpie.widgets

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EcardWidgetResolverTest {
    @Test
    fun handlesUnconfiguredAndPrivacyOverridesCleanly() {
        val unbound = EcardWidgetResolver.resolve(null, null)
        assertFalse(unbound.configured)
        assertFalse(unbound.showBalance)

        val snap = EcardSnapshot(
            schemaVersion = 1,
            generatedAtMillis = 1_791_763_200_000L,
            configured = true,
            balanceText = "¥ 86.20",
            hideBalance = false,
        )
        val visible = EcardWidgetResolver.resolve(snap, null)
        assertTrue(visible.configured)
        assertTrue(visible.showBalance)
        assertEquals("¥ 86.20", visible.displayBalanceText)

        val maskedByWidget = EcardWidgetResolver.resolve(snap, true)
        assertFalse(maskedByWidget.showBalance)
        assertTrue(maskedByWidget.masked)
        assertEquals("••••", maskedByWidget.displayBalanceText)

        val unmaskedOverAppHide = EcardWidgetResolver.resolve(snap.copy(hideBalance = true), false)
        assertTrue(unmaskedOverAppHide.showBalance)
        assertEquals("¥ 86.20", unmaskedOverAppHide.displayBalanceText)
    }
}
