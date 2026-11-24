// Adapted from steven42121/techpie_wear, commit 8348b36 (Apache-2.0).
// GT 6 Pro diagnostic port: compact lazy point table, Lite-compatible arrays,
// and a stepped signing entry point. See LICENSE.techpie_wear.
// AUTO-GENERATED from /tmp/sm2opt (SM3 + Montgomery CIOS + Jacobian SM2).
// Byte-compatible with Dart Sm2OfflineCrypto (verified against dart-sm2.json fixture).


const CONSTS = {
  P: 'fffffffeffffffffffffffffffffffffffffffff00000000ffffffffffffffff',
  N: 'fffffffeffffffffffffffffffffffff7203df6b21c6052b53bbf40939d54123',
  A: 'fffffffeffffffffffffffffffffffffffffffff00000000fffffffffffffffc',
  B: '28e9fa9e9d9f5e344d5a9e4bcf6509a7f39789f515ab8f92ddbcbd414d940e93',
  GX: '32c4ae2c1f1981195f9904466a39c9948fe30bbff2660be1715a4589334c74c7',
  GY: 'bc3736a2f4f6779c59bdcee36b692153d0a9877cc62a474002df32e52139f0a0',
  montN: { Rmod: '000000010000000000000000000000008dfc2094de39fad4ac440bf6c62abedd', R2: '1eb5e412a22b3d3b620fc84c3affe0d43464504ade6fa2fa901192af7c114f20', n0inv: 2421 },
  // Affine coordinates of signed comb points. Block h, mask m, top sign +1:
  // sum(sign[j] * 2^(128*h + 16*j) * G) for j in [0,7].
  combTable: [
    'd4zPifa0I37MEiLmr1RnIeaoWmMhTJtYgoOJ0dIuecxi+WAh4PcDX0Q2ysZZ9WQUXUI/X1253F2zq3icJj916g==',
    'Qi9W6ygVUFETZhoDOH5kwa047aFWKdSjS++otvt1ionXGpyt9OaWj3iLQxDvfklrHx4ko4xifDVQrE+H57msGA==',
    'xlb+ncvJZqFOOQKrsa6bpKwQ+6ZSKtJrQ3VaV+Ucr3YXibITEGvoo5ux8muKKNiHoWJcF3OsMtZy8DxJKRiL5g==',
    'Nks4jBAU8n9pVxK8rvNdRYx7mTnfTqEqCRfaUc0od7uqaArTsI8xDaBDYIz9nl8pZ1/Rk5PD7u6OV4hJlTMwOA==',
    'FiUpp+8qQPKD9u4ufAvzUwZ1702V7OIsHL8+nOLLTaEHcIM+KQhVYZB79oKn+9+KX7Xso0ven8fMw5u43/MU9g==',
    'IHTCCEy0sKe0qCKLp3ZPIKfdApA1rtvohRzLzt/+UMmdKyJRK0AcKNKySdaUBvM38003RZOzGatCBN5LPIGzOQ==',
    'cWjWO/u7eTe7QgtSn0rnPKPAygQ9bRa5ZiUdsoSs6iPftQMFPhzBlQCLiRJvHVpMWNdtqCtxtL2ugL7GRnAS4A==',
    '3gcsJYHq9uSOO12JEhVFXwIAh1fu358RptiFZ7zJkYJm1pYdshOUUUdbClPwW5oF8ecvq4ZK/cDa/5+EkyIuVw==',
    'BJSJUOPyUWAn94WyZI6WupwnbLP1ASjFsh+xrgpQXv0tMtB+XouQrBP9nNQZYquexEtFvo1MtRtAinmWrmRIcQ==',
    'mElTMw1CEnVwNmnvZoEsJBh3MpCe2dXmGf227rQsl6E/x4pBNdJ7ByQRO8rbZARt5hjPmuRhbyAUxVdh7KBu+w==',
    'UglrUM3GpJ3dCBQliuOfbgQxOZwmq5vy1QHKSuUZIT3pnzMEMM3hKTNxlnf0og9aRfSCN7gXVthJ5dA+BL0FZw==',
    'of30n8+9fUBohDN4CJVZMCeaN6qSUeA0Pyqj1kUWexI4tuLHRcKQbS/258U261pm+dmAuZRDbsRYX/bX0SnBvw==',
    'NMs84niFehTdQHFYJs0Pzz8FzzNLtNEKnYuIYRnTUYAuhiLkBxXcWl7yP5fladXetH8TqdrivvU77Ga99EG08g==',
    'IIvofO9CNEs+SL5JqB3UoCRYcJ7kvxaMkSXhuhtWYPQH6ry6j2PP3ULbRBaTTRVspxgJbv74B6H9sPkSCBclEg==',
    'NvgUHmaCfEnQq9jtvw2BSsQfh67EV8rHmimbLt0xyPSlm2LFCLkPRA2aEkDFqaTga2TU7OhkDELGM2UkFr6nnw==',
    'P9qmK8snDEJlaLDdCPklH2Ht3e/TZ6+V9+GY2knTW0BBjgreOE+AMCvMWo0OCAf1ekL+/oylB/cUablXTcbAuw==',
    'G2vcYkD2DHREBib0Rwe0hT1am3DjIs5LHHsx5MZpSdn+IZRw0oq7QGzSXZ9ba0xLmHZQNTtezkuY1XxkdIT5vw==',
    '85+VoImJkBk4jCG2i4Ylaq9xp5TDj7c+ilqWIp4zt8c3N0pmMqOIajfix83qaoMqpyAZAgjSdzZE9D7UfTUlcw==',
    'g9RIOf3fI/JOmchhuyLnAHGRVCBO9lGhjQ+Y3LQnE/kLd+A4swqerQH4NYdIAoa9HurNrAzquqMCKdm+2TGesw==',
    'Un9XKPGgTyvF25cubyQMR9sCKaXd5vV8/D5RQqJyTOdD4DVL+VDE6dWJR6KDAQlBaXqeCEZ7EjOhULwIV/JUpw==',
    '0qVR3FUKfqAz8vi9CjVhQczeD6t2DETKfPujWnqeV+atNzJgPnNwhl6GrAF4AXfY861S9RTOalJ111aV7arrfQ==',
    'dbevqJs3vAFYd2P5CmJvH6QuNf9gkPiwRQ4uLhfOdFtbogsjSShSGKlA9XWwzX5ilnwMjjXRydBZ29WDxVnU2g==',
    'E4sECQGIwzODHpkSctgmg0rrv+SPZUXXR99Ad5TFObQdQO/9wwQw5W3VaNAHseWPnTshvph6/11BWCdSb0Zxqw==',
    'oIN4cN+iiOhgxaWK0DFX/nl2AHjhAtYDpKfexW0gCn6z9tgNikfF8yE0friT9DzMBniNChsWvzGwbWWCCpK0Og==',
    'qycc5wkjE6fkU8+TGbjNMXtCWiF87tcO8uGB61191ni5B/NCJytxTqMEm6hAjTdXyDoquAZypOunvq6LnXs7Vw==',
    'USrd3o3Krc4a+PfM60mgNDMEEymzKhsWwwh+YwaSaCl9xhWN+/3hBCr+z9ri5me3Vq3v1FcrX7QRUaMFR5n/kQ==',
    '6DjaTyHvc9MGInu3wdZruRbRPDRUCCQuVFKpAbPFSUim2FU+gdoSW9JEVdcDk9+ZrGK6Pz1kczEQiY44+ODdBQ==',
    '81u28lVdkw2NGRlxaQVj4t2woyOfhRlzREy0CEb/QHSpJOqQcCAcRl3fJ3qxqqdSHhSRbDyVpg9dTGWkyWzxjw==',
    '1TIvTMzYTzcx5D6QVrCnu/asE8cWNPoUzzOopbNyT5nJ+2EU2SgCmoVi/QcLyHshfwZM3UuwHa+ndZD3c9snow==',
    'GhiqCF6krbiREsEXOt8uLAD6TJF0Ubxxl7meQ2JnbXV1xk79XzefbkWtY3nY9L7cqBDfVtRBTgVewry7YQDxkQ==',
    'pgWdIIs2PQjEnQ/nNW0Qta44Dmk+/MZcNqU+cxuBxe1Z/7m3OmgCS7C6h/L66FclBY9jP6INqLD2+J40MGueaA==',
    'z2vtVANEYiugri4HhamclEe8N5mEr8T4rjLS5Ti0Tj6FnY82jRN13liM1EutRxqI1agSZZEtwQ6KfWy+sz9rsQ==',
    'YU71drTvmBPGmVlzYDcGqTj+u0zUTaZIu4nRUtaltRK/TFtIdMoM/O+IGqNzi6c2lWLOXKCfERGGIHtA2zDqjQ==',
    'g0Ibw947ztL8oH07F+J3naxBMtCqjHPF2IX+q6DsXKycOxBmhgoQZMT43b0EAFHxOdwqPaFNg9NLmELPwWo+dQ==',
    'RYj4V4aaJhTEhJyetL+B3HuTb0TABqFg689rVbvGUB2oeR2UZwZByB4WtlE45+2jaPFm4OaL83ex2+iBXO2o6g==',
    'zGxOsMWRuHeewlFVwfZgV9GJXO7S93MmxthR3/MFDv1Ecxgj+WPFRrzO+BVieIbWp/YErihvc+crRC92djBi3w==',
    'd1S3CQAWbRH1qBx3N8hZlH3Ul0DgrpogdXbXddHObWVvEzZ6pHh29eFdRAYUGj4w61eSmXXTfHigLFAst4ul+Q==',
    'HuHIF6n8h4uO+m5kxQxUgINXArsa4LCGxs8d7OVhEZltu9Ny1eC5bE3xSeM2eAMClhHnVrkeF9AUbFdDDpQDeg==',
    'MLFu2vJNNNBAtQW2dqBONWJ5AJa1AWdOlmU6OULRYSP3o3NRZ/3VH3yb/fu/cxRX5l8CCqq0ubH2vKQGAbp76w==',
    'Vu4dc59wpDmXpwRyi+Sgz0oyfln4N+WOWOHdCGdzVeWeuoUXT9Tv/g8MV/e+h4YI4fKrFNEGzvRcUN8rNbmbLQ==',
    'z3Sg48bQIRCBG5KckwwhZHe50L9w0QzbmwiG3SwLmbq9NcxhHpZQ/44xvFCrscHBZ1yz0SeoU8nYJwA6LYauWw==',
    'lnS2xEU2Tow7bSuKDpZar3Vo1jHu9uDnDrq9h5/T/CmF22qcWhrOaZrQsQ5LJaYGdB1Z6EFRqHxGbW1UoIZ3PQ==',
    'DGwExm1AjpSAym8RAsJLPDc8fGZmQyGkRk6pzJkRwpD19kQeVxfe5SPHrJYkuFGN+WMIZhXueqc8MuUn9Fow9w==',
    '0OHpS+MMofiqyKDK6mZSNQTMeJE0tD6WtgCf5BYdOvGjjY9VfjIRWSreOL6CrHl+RJoIavoSLP4YAAhiMifVsQ==',
    'y89Kaiacw0zYGZtf4KJP2DrYcCBYfE5DeDoXhczBpFmu+wcHWS+gSiuCSaakq3iOij6PMi+AURZ8Ro5O5b1KEg==',
    'DLy0G4ODtfqOsqbcgclNv/gp35uprnWpQiTjQYujtbVEedVKAgFXjZTpZcQhUHN+/P/QnQu0ZqtCH/K5ZSf58A==',
    '2Tq0X4RpYLNvOgDe1ZGZLHr7wtBiUbVTq/eHww0r/QBJqmjjKbP5bCjSHdT84wyI6FSuQ0Q8VfYfbkgQJgM81w==',
    'YbcuMPfhtYBjTIyk1wSG1K3SOtVqis1HDSTIrJUSF3trtqhTG3qDp2g6Ycoc43yC06LLorthTQEWFB8ak+HL/w==',
    'e20cnleUFMzE5NdI6BcHFA5vgORaU97jMCCTed4hov8yoP7x3ExENtF0e/ypryp7X/X4/HlG8fhOs/x1bwi4/A==',
    'hYq41hWw3PUinZ3CK82lhvpA19bGRFkR0PAfRG0RSDfeeGx8kyhFuO9e+PCV5wnWTDRukm1DiNpO8qQWeT0NZA==',
    'B2alEt6LPxs7kcpB1k/LmMqHmtUr2YOOJ/Pw5OSqaWIVUgjr+FHGawNAy/tc6aDm7DjrQMdpbtWr44nFvNaNKA==',
    'hoY9PaSKRG1Se0Pp1zw8yK+1oT31QJXFmNh36sGyahqN7MHywj11ERefN++mxBL/rcXE8WMHHoZxVhqF7nx18A==',
    'tGhgjGo0u/043k1jGWOy7xTyZCsiwCg5jc9/G2iv6TP3vYJ3N1FaR74BXTcr4tjwZ2OeWrEE6M1bL+kcyQdUrQ==',
    'k/wZx+uIHdnqYyZPmHJAQqiw18npdYQ9kdz8FTXeHLd+U6T7kkCHKKPmhIYSqwkN3zF0x8oDVNGrnFMRVU3kAQ==',
    '21tb7/LPsjhUSkqnaeeE6U7Ii2YZSv4ECz1+ZDRQZ3RAHsw0YBamFe1Ar0vpa9nND97PAUar55cqKXdfFCzuDg==',
    'N3UYo2LefTTHc31Q0dzO3ygAvsE5ywV9t3YMj6Klb8M+2eQ7RUACmLp/7nk6PVQqfQ79WlaeQ7sAsiFtXShE9Q==',
    'Ku6Uqpjm16hpBycYdSDntspA225bWGrM5K1QIE00j/Et0t6ltu9cL1gFw3JDnB1xjl6QURu5dvHUyfYtAb+X5A==',
    'TvpbYUO0nu1yJ8tWFeq08oprzBLICG5C8ZWa7XxicDQ8wGQxhch25w6VJ//cj4nTMulve8TIA+qFvwW4gj1jzw==',
    'GQStLkt0PHUpvDd+kFSz6vyJb/aP80mass7u65V1p1f6OtJ6RvxJ95fEAVZs49brDmJWprD80/2/bsKV3/FjSQ==',
    'kFap/wXRYJuuEaqAGerKqTD1ww2TFjC2klBc2EzSxABmPgLreNDv/821m6gtuTgR0gPq8YAf/CcRfHlGAVEb1Q==',
    'tDm/CFRiL4cyfzQtV7aXNK3HeMquzIu9IA8aug2CSS7piYUDwZdx85u/uqRZYYZZ3NpSP3Jjy4sMtdHZZyxUZg==',
    'bUlYZyP5az9n8Evp5EXDkKS0/27Et1xxxya8ZATsKUdDBPpUY6YGULNfF2cEqFTOf0Yu8oX5WEqGXQcFEkf6Gw==',
    'eQsSGniCAXhMK7KRMezhjk3yoewRBzK5URWmWbpeR1VnmHhHzbgtYk1zN9xCTut87t2ZArGCUKWxP7x+0piG2Q==',
    'zo7GP2atXVG97iStHvwl1pVGIneOrq+2Wu1q/PTBkbwD8s8zbCCeRnme+dCzmL8pb/ygTIYj5w/FT1j7Vx/OpA==',
    'bX2M6PJoCitQcPKcFjEjWbu7mj+gWqMC44QPzxDx8JXozn6NfrhFqpLqwzQrF9Ltl9ljeFM9pwEGeUsCoI14UA==',
    'oYjoZ77aCSq18se8sdrtQYNaGjdtt1GrG3QwBnVaonzTAhQjIELp0GAjHi9h35s37/Tx+YE0cAL+5OzEszbSLg==',
    'mk3DnwXEfgzI14mOdX14wUIHb48aRkPHTkHXoDNmk8ROnUgofs6gCG4rnjoflQ6hWwMPLxbI2Yu3AP3fCBjgMw==',
    'VN+2+fuwkRMpxvzRnrM/u7QKoPZNbf0OnRV5jSS/ET6WVotv06tnER6D8RD96KVqNNpz2DvI8Fg4gWEHT0N2dA==',
    'FPejBxW5kLeC7Y0std6YbHf+txYlqjnMv4AaTpcX1DSz+nLB/8sJH4X2dg5edHUruvVT8DOFrcwW4V8uudMJgA==',
    'yPb/EPCZeRgv4RoMUOpZ39Fyqp1o1n116O3RT9gN0xgkWLrJw+pHtaXrONG2DhDuXVsAnBSB3N8lVQbTb9S/Jw==',
    'NJc1g4pI9On0/5ix4Pu5xOqTRto8xKZEOvViPQgy/3KrEn1/R10aOaQawwBC9g0MHJ/HrLCjIXvN4bzvkAxOZw==',
    'bS/J9pIDhIDge2fyNEmSfq188Gfdtgx9RFPS0dMJxUGRVMQcwXtbUsvS/14a9NEks4IfcXA7PluhtKNMahRMNw==',
    'naSh883grDwk1uT89Tr8O8912Co5wA0OAXysCIbN+bXSFPNp7FsH5UKMTPrNu/LfwN9Pv91utVbkWaFrFNL+CQ==',
    'OhyobARsVPfeuFv+5LKvMe/62aavMNAsKM/W1w/THCBGjtLFEAp3dg27XHvWz9l3Wx5MKRDcW7tTayMUalVi8w==',
    '+aycLfidePw8yivb0PiMstQK22xKyLz1paSvWlEWi5JO7VZhFDJRQ4JiJiMkeUMw/DpQtS7SBgM9p7x2OIMNWQ==',
    'pZfqKequJq1KiP0BsLh9wC+vHDp+aFTiHr9puIBYiS8xHts/LvP+hiZCPcOq7bZmOD0jXrvFjI6PG81VH0dXCA==',
    '+eee+g8lLJZAEige+bcU/fTnHCvpZSzgt/cdvsssHjSACbu0me3hTWAi8Ej/KXzgBIS2a/Mgb4+PAy1tOEp57g==',
    'C3Kwlmw3FG7hLqgs3GSg+PJftUsWs/+g7uaV8dDEP6LoCZQwKPwZ6SObQdVhGfKh4999VGprnTxZBxPNYlW1Cg==',
    'id2BKM10yDOP18TJF7orWB2oyAy5gIpfEyM8TpKNe9cxRg2qwxspujeQh/znk3e5ksnKSSa4jGjBtuln1IVWYg==',
    'B4dJuzetl3fBFM4kaBaP94S/6AhWm4oCWC6SDhdToZs1ts3PMhn/1POXnneRU1gee8OIEmcHoN9ovyFz4Eul+Q==',
    'XKBijGi4kBaG61ZkyPmACxj/M18zBpXCHfdMUuSqvV8kd6qCmXJbskQ7iyWEAgBepnnND6uFAVYEVDlaWjnCzw==',
    'hggl8FESixjg8iPGCej6OIVjHLzB9ERil0zjOYxWFkoIlvs/pdIUrDaveW8ZJXgnmJ1csmus46ZarG62dkOltg==',
    'SEQpsC5CzM5DfSAQQ04ximJyBDLY+f3RVwOLeVTfk0UACe19HrSAO/ZezE9Lbes+uQHXPIt10o+NMDDjUXGVDg==',
    '+SmKZYx9nKor/f1Ahv9O4YylvuwpnVWljBxaQbKUAQrGZcq146FWga9zhJMBmywez7KxkclTMMzcsmmzki2Okw==',
    'm5GnZ1kQ6M/Z2Zp8cz515UVAa4Dely1MDr8DwwVWnWu87g/icxetyCVmvt6D/4hIOKXKAyzHwdrJegQlpBNj7A==',
    'pFmgRrefOj+2FlMYQUSa0KcinA+JXVKMB5KeWENKeSMp/N14K2u7sKC9I6uEEYsQsqQdrAixQ3e3TxL+KOR2zQ==',
    'LeJOf4NvvA+Cjd5Pjr4I77bKPGRTnqZvZyiwlypFgyU0OOtcjGY56F/103lTdLpxns2FK7vRZh/WgKcQBFw6dw==',
    'bQA6r+l+VI8+Ibqp1ND2fAOWKYAWDdWfOtXpvCl904qRZnWC3J8/ddFxozkmqP3Uums3Euz3StNWaqqTvuFjdQ==',
    '9/7+7Hp8lZGN263SPsmfcWt5PUDJoNM0L8t+fxttSgzIhX+esPJjCjB2uyLZHemm484aDrAjo9WRAZbWCQmD5Q==',
    '0j0c6sv68stoNCSe+GnEhTMX9KhLuQbbnPMEH2HIv9RLJVc18kafE4Ubx0gwLeTn7ioZCvES+ddWAXorw6/23Q==',
    'KNXjnXYIhxXLm7KX9rhZIc4gewPRp7zXLywKIDQlzYpnFbnAws8piDL+7iwTjabkApfmGZdbk/9puQfsY22BFw==',
    'yAvrMu8zmU+yq2UqTPQcDt1wOannRzdEnGsEiMrR7ZQ/ypi3VxjwlKgB2zIow4o8xWw0TZq6+UyyMZYPYFFCDQ==',
    'Dh32QOe1tN2zUI7Ni8by7cM2nMOtqVIUFgXfoY1vGyuXL8EYEkT/xe4Nsk0XkcyV10VExwvguDgb9CplL34W8w==',
    '36nk1ZKuWPdd2LSSnubof2tdsLRsUHsvl++vdBqAUqWzMf/T7pyu39SfRhbuqEDzlJvIuSqj3CrpMUIlUhm03g==',
    'fkFVS6KzrpTkc5YhKtLizm+477pqXzkL57jX3OHXNccJppAzf+o/y1Ls3RHbGPju7mVIwJlE9ngbc1JswLQUoQ==',
    'HXBDlZo0bM6tLDJMAYIa5EkdwtQP8YcLEOb4FY5l/EyTb8ypzn/UFHYkRNRIFRpd6wgbqJ1GKzi19gB9mzLlyA==',
    '7K4KAsAsbW8Lim9yMbOJleKujj7zyQ3ImwMi5FMrCZ65T7dNvKruUE+uzKr+xpVk83AJM/o/Jz3O8pmJtW5/KA==',
    'qYhZTGnP64Oo7uvK7TpeuPpKjllCOcj+JDnobfgnSnWEXLjwJsvdvHRlh1LQTVYfaUKG/WTNTZis9TedAoGgHQ==',
    '78CkJTkb7UkhajljtOS3ZT8kuToLnw3wBGbJAWlElSUCH6oTeP+Zy+GPBziKRNREvQhSxhBAufywsl6n70beQA==',
    'H1t0fwkZ8MNlAc4lLgmVTPxsQuYAg3mr1N5/mcgCkZqsMEzEstNOgOF61TVjqRUZllZAunz6uo215TcROWzs8w==',
    'VCDdKT3X5b01mx+fRNe8er/bna/K29k2Pmk3oivQ2ipKWB9SOAlYnYGv1EwZjIagEBTH4DquqSQS2Pt40zmRwA==',
    'Ek4FEEa05rUj81g6F9U4Smx8vAdRUp4EXpEa+fl0UthiFTQtLV6KomaD8rCheL6iTve064ExtNiAgNqyHGNIyw==',
    'Rcbfe7h/t74e6BU0WFfL0Y9I8Ti1mcbgTS56ijWfKOLW5M+9dgBZh0LX4iqvJtSFvHuPd29U2tJ7sckFUjiAKg==',
    '6QQlj1vmKWgYL8a3TYUR4vw2G0HSXMjbmTeqNCpcfjiDvPG7p/jncArDLfyS6vJ8In7wlEwQK2iSPylSOrPSFA==',
    'KVrh1xqV/+mgIggC29HtWQQgvc+D0Fy+sbl6In6MyGjpT84tmXnHPE9XuxK/7ersJagRZPrdSRWaYOqqBygfhQ==',
    'Znr8fM7v9LP+syX52PbDw3lxPeKql73ZVsbKd69ePb3n2WrOG88Oelv+0dCLRkyDBNOyzn9ivhEInnivRnk5Bg==',
    'JQ6amxZtCGxM1jRMLatVTc+wwZlKu8vFbYLeP5poDDWS8AM2ujB8M2rpHUgplq7Owolqr0EqmEI8BSce97oWYg==',
    '1HTtQOeQ8Ewcrc/xnkoyeq3VaT27rqNHS2c82ExI/0+PTZ5FX6jSeRQGJPEvEb+0D1n2raEfeS8S0w+I9QfMGw==',
    'R3wX2NfbHQyCe7Zn6E4+M0Un7aAB63sm0o01B2u6+VweS9O3gXr+/sWj2TLiqgyslIpwI+hmnZcXYVZZwwhI+w==',
    'aigU7zWa86CQmFu0hcyIzcv8xR3Ny0Rtef1hCZzVJUk+jPU8f8S1Xqsua7wr9YlNCEz06vAlB4zKbDBspECpOg==',
    'xP41KnhUVXUoC9nQv1H6zJrejelZSYT8ILHvIWzNyA6oRlP2Eck1NSVFKPbhL0j25cd90RVwwmTb8C/N1sXfvg==',
    '9+uSdEws+wZSJHVHp3hix+UcS5pmiz7/rfaL/Rvreaas3Mrq8WJQvw3NligLBccVE0JFI50q+he2D3+LXE0rNg==',
    'X6J5iJk3RpB5oyGwzRwAOhfgdAYQ1UUicsaNv8EcC8MNqIq+EHOCCFrSI1kgq0zvVG29AlPKfyVqu9J7nwVoNw==',
    'RBTyNvrvw1BlLYzNePhfWbWApKfI5RjvUfUzVS+hWUhcR+bvsrnH5Oy8iUlY3n2GfKqbwBAXxYQLzTpI19TTbQ==',
    'sdiljRLeQhiSjkq4gdDJzEEWR7FHzhK27aA+gXgwn8dHMHsMrSNYmAZFJrv/xH0FzO1bsF63cm/zO4KDHjsXhQ==',
    'sX9+ho3DHMGy5oGy1Pe2R7AuSSbUvJPAuuAKgPJyktLWA0S/xRKToAAEdTjo/bmUd9cDgUB7s/qjDcokwQm+YQ==',
    'otmYUVM8yLUroV+AMkNIyX2HapegaFsjVVE2FJwBL1e/0cz4uwHcO+djyt5i7tRs4I1SAWYUKMIJ4kZH/XooQg==',
    '8UY6izXWlUPajpflsuXW7aoRl2lvWB5oKuZLIP97SdQ5Pk7x0kkOrTDL/d9qTC5Q+ev6aUhhVI/4IxHVdfWCRQ==',
    'c0mSS/h5yAXFYaNHarJEubk0iZLFMoFkBMsfGgWplI8bg+UAonMVBxC0bpdjya2sgFptEn1nllQ4Es8Je9bG6w==',
    'htKrwT+/k9LVGI5AlYTw53ZjZP4196fHmOs6yTK2AUd+v/G2EzHmZMBAKSfJlbYKk24efdUCS4nU1OwCj3SOyg==',
    'O17TjG8wLONjZ8S9sOy5c8gwJ59h0mqwmNsI9m85mk+EvG0iNW/KcLm3Dqc57ghQyUf/IT7x9crLo2R5CC8yQA==',
    'mhyEORm3pIe4a0AlTMbHiOdck5fvZBEXAY6GT2PLKf/7DwZLAn2C+vO/qExZmwS+9JH1EhZjUPguJrvE3eSj2A==',
    'QLW0/FpchHSqFyOLFPbp73IwbA7PnOw/Vei8L3t8UdL41vOVI009kaSpiKVF3nsmoKxNqtXHskFFYxGSjQd+uw==',
    'IHhLqLzppiHBC0cIAC4DyFprM/ECwa2u/br0XShEg/fCeIzsOtg5F42a0RhKv+EQ59lVerXlXuaoBzMslhQR3A==',
    'ahQg7ULtzuZ6D7IaIGQVl/rQBUeP/KFyg5ASuU7Hta2DB2cEPovfNLRcFI8GdgX5734cW/t55fWLHxcYQ0cEzQ==',
    'tUkJTeXdDduxYfEZ8sm6GPGycz8vUX1zV/qNsiGjL6VXdH5j4zOAR9HonG0QhGBTnbPHKmTTvr5b2Xofg6k4Bw==',
    'eglqjt4Rh0iSvoVy1sDI2r4aiSuXpxBui6sGieGlwC/aTI7uOeDAN4N+KJOlXXJ33e0jT8fjrnEbdg74wgtSCA==',
    'DiklZvzobSJE8iOBnEE7qzO+lweQyPLcD8N7Tdz5zP1KpWYboQ4QPR/ODV54Fpefg4EQwZGg/1KYLSad4Mz6sA==',
    'xnZb++8Q66wrNFd4lRuBUfgDbmHP8fBsQr7rL3I3QPFhDQpW67E5lyYJkdWzZdPAAKhuucLSaKdq0tHADUOxRw==',
    '1vREA5ftwQOcblXFDSpuYjqxTRyao1Exl9aCrxF0ViT/RLCPW0HC1B0oYM+51DWT7SuQ3oCc9DBTbcUjNdiijg==',
    'qozL93aVBeY/4oh4tqruRtsLRd2zI+I0CnItfegXSfim/UdocnUwjqMEfmsx+fxBYx5w/ZfQUscqyHIU0sMF8w==',
    'FWuS7HoKtYg+Q4SSForBF0OdPPGgphFm0W3IfIuj8uJHBpluJSRbr0k93TEO5XtthLR0+dAe0c7bCIMs2arelA==',
    'e9UtPZmml0yUvFTQeS8J5db9nqsjxn5plRQVH+Yrz7pt4vDkoJLYj0tYv+14cXwwXeK63E67yBjjHlJnxIwr+g==',
    'io+P64qMfxUXeMDwBHzjvvfgzRpRC/o0xsWSaWacGYQLZFbaKBHYhNu4xlYkedocIfIUCAAJZ6JRa4C393/Idw==',
    '5R4XZOheeWhaZlMXXnMcWFDJUryf8/QYFdlBIcHc8rF5UiEL65Z2uQ6fkHS1MBV28GMQpeALzODZ+xO6L9DdDg==',
    'ZnIwDfVV3IlR+jQA2PO5p2jQpr8AJhzuZNJVmkVwy0yq1hZEcQwP/lFURJpQ1tM5jATkNBZTA1+vT8kAJ5yyIg==',
    'TtrRJo+dHc5BFxLmTbQE3YiNVKEn9v4uxcJaAER3qozdzjsoDZJnE8EQwWDoGpkfiWjdtkjtnwpwFBOsFBMCfw==',
    '9FrMo9hg841LzssB/cMI7uAYNfPE/d7cuiAdFPt5G9OlAae8hmHPsrHGzoMmtZdIosDbW3+T/lHASe3vFDKYbw==',
    'iDVivBNOv6e5Md4Z6DetZ1DW/Uoq3bx1rMcuHvubVux0HiJY4ro7nwpyCg7G455nvvtmKflv1RhsylsUnBrvQg==',
    'oxcsOCjEGmP7Rbvhbn7EdQPzdsQBRlC2YzY68JyOJbvaDNwvvA3/AoW1fp2ToNH6356DU/oN+qi+FP1gEoCzcQ==',
    'XCN4rACv21zELLBajnJ1PMOspGAv8LECYKC5E0TyTbpz+ewZfi0dN5l0bmqGz8vnCgdOdkABhSGsr9dT8O+Z9g==',
    'D6p9QrNlAykeWoIX9rtVh7BuRz8LiOKv/lhEvzqvVxlRAw1fsPTddzGL0AWfEP1COLHaU1TwKgz7Ovb4BosdnQ==',
    't4y65KjgzXYO/NQ6Ai0BugfP11Fg9lS7tBEltltYlL89uFTw0xQ0jXIpggnqzgrOsUboEWca1WKZ4PrpQitiwQ==',
    'ijlvIht9WGSzPIp+1cb3DyoZ4JuSMbAChfcX0Pxu8O3asghsi+ghxIw9EaQQzovP7JDsIjSkgg25Ha2NApk9DA==',
    'wnB5fAPAfB/cbeNcmP4KCpx/uN0fz+BFk2z8VQRnaYLyiE/7XgrV7hw6GXlapFZ//mFx1nUnkaMJgeCYsPGtZQ==',
    '6rRVq9WC+43+mxuAqXz1tZUib7jr6qTHRQ3RT1kOj+huqmstalYm2/I1zRDigBGrEtNi+mcIiG2aQPxClju8yw==',
    'ZT/fQDOLg9hYESR7Y6QTfCvoVsuV59TLNaeoEHlvqaFXxtATJ+XqIvCch0v88CF8arHf5Jhwluh58SlC6uAfrA==',
    'wTZTMAiB5NKSX+urNtMA6R+AcnyIwrhPHBkEIQxT31EsW/eG4g6eLgmsxCiHwAraKAIIEqteBWCs8mmsbR5ibg==',
    'v+AVUIwUb0Tv7MC/68CsWacDHq2iJr2pgMzjN4zIvQ1s9/lNXAPxn/KzCxuEKxMd141xrfSLN7XFyLvAO8Uhrw==',
    'aj79qBKqNHhYNyW5sEMGKjBokSHbc68PHlBwT1HkYUxObR0CDIQPtf/MJwlCjd2LUZoU6Jbx62rQisqsZC6y7w==',
    '9AJd/OUCTvQmIIFwAjycNsCLLaraEiS/54NYFmgV30cORQK7fxCCn4EaIG0Nnl2BM08J+uCvIjetBIbRRP/XMQ==',
    'qiKKHkiM6g1DY5KKpfcqVzCIl7p7GpJKvBGUZ/Sincvd0m6ElSkZ75TRKpzKFFXNTA+laC4dS4CCoiBMm5QIbg==',
    'LkNcS/dtF2jnVrA5CA8/mKGtXx2YiwR87Iw31k4KnKiEiTsflcbhweE6Zg4mjhTZwujmWkE3FEh3ao4Sux1Gkg==',
    '0Nn7FqBohf5jxogyJ2XZMHSeWUb0p4MJal7NAUPFGZONzXeaEkSA/8WJ25OIXnRQD1KwUaZvniwMokPYmSqBaA==',
    'LsbWfLIssfUPEhdIHDao4NMG9EiqVzSAsQEcuXKAkiBbTlqHlUIvwKLJ7FVWToaIDY5OxT5APUScDnx9grD9Hw==',
    '1RtGGUk0h3V2OXvUYREEV+AZJ2J5WUClC5GybJU5ahDBvBPWhCpTu41CfSWHyYxw8t9HZfCGZfSsX13Pg4rvwQ==',
    'MXIRLuRzSoyoib4k4LOqJNuD0OWQxnPRbFq8LKuAtJt9E5Fiq7u8O7sU+/JjE+BhRYfNl6CTWUF9nIJ9QE+gTQ==',
    '2h+jYdS4QjHYympWzaj7ZZIWXdrc5J7fIRW8W+z28dG4K/s4wlgChRALs/OS5JlfPiWnX6sZwCfPjA0F40HUgg==',
    '3pTrNewyHiw8irNq3HyyldbfeJOlXN/SjE/Ns9HiBLwlwx4trnRhRY5xW8gGCtKtxrZFBjENUHd/uWLrxPEP2g==',
    '8kqwdJjO55wCf1YMDI2w6TBInBx21zi5Sw1tPBmYdKGBIeThROng+t7vRP/49uNdbeX80SBi2B+Fd2B5QJ+a2w==',
    'LFTteRwc1ynZFX3DyYgWsSHBVEnc0lSnqtboQV+1mLoFDq0h2NcaQuwU7iJigNN/XW/I0rIPe6ofvD1BHBJmoA==',
    'R+5VyJOLSBfBnnUSLqBMiVwYkKE5Lu+2uH4+d8dxqZkjm2KebaysIvinJnNAoi9RGs7JdiIOhWWZypCwvntr3w==',
    'T3Yb0Pm3MkQIJHOlSkpQA4H3dvIHZnC0jD3Vtyt8lhc+bvRq7/qCTnE6l3sv3JhHMBm3K2D0m5zuVBPUvhPf6g==',
    'r8TGo7jC3/CFxBAODaBjY8SyRPlj8muxDbcZC6ewUS+VW+rdHybeyTgQU8fst+IlxuGdbXqAfqbpcZiSpT9nYw==',
    'Ar8W1BExuba34Laz27qCorfKKLhpckaL96yfzsmT8+3bZVdiyqvOslfBcXCy11It7EPbJND4Xy4zJQ6BWArlZQ==',
    '0nBX5+WWnW+hCk+47ywUbHyoNDf8fwOZV+r6fkrvB5+EvPizslOG4ECxirM9Np/eimjp/SDYExQwIrJn3ipBHQ==',
    'qcRBw+2OzB0fXLoDGkuZeT633JP3gX/IKbZHCda3nAzTFovGs9C/u9XTZ7P/w8EJ5ZCTbXwiXFeTlhI4FTBTOw==',
    'HRc7tjvIeBXS3BW78uyNvUkKMC8vXeJSTkkDSpFrTjAu4Omh5MgNT2uC7bj3egw661RN32GBMZrgQj9FHR4JxQ==',
    'q2fcaLzSVfHCMq4m3zBeEN+g7jqgaNAs3Mrr+XtuhaTqsjLDxEu6iiaCJl9JO6LWU7I14VzdzcK/Pr6U2FloFA==',
    'Vwzqo7br/7XpmKoEsrq45VAW2M9CSeQQ7oeOOh/FjNMuYG7r3OZ2/iigcmR5ZE4S1w2WXGy5O1O+tOKbijEyEQ==',
    'YNwzxnkgrm6bfJRCppVYySIWYP88228nXXYxheiqbKI/vXtKl7rwT/m7GCUlksKV2m9/rhFAMAGlmWbUouahhg==',
    'Y1ITh+VntgCVa8Ar5t7BC5IYWHVkDtQxmxGjBIoP5r69x4f2FwJyW0/m8637lCA9ryfjhH6qF/Vz8JZJpwEoiA==',
    'dkAaU44/tfEHls04z6lXPSPN2oLAkJJX1zmTmwX1hFTLn3490Hdi01a7SFc6CaYNZou8O6E6rTXJRD/VEZtVng==',
    'P2sU0Kc83IWXkWfoWndun8kLbHchA3dBNZqim2huLbMCtRjAuRvsFC2wcLNtsPs6NJR1qsnQdUTILDADSjM7Zg==',
    'o33mLc797BAj0yXQsWxPFzTVjwyLpD5jB/YPdSUelttCo0+RNMv034mjXr2w5Brcc8xG9MWMck5kepsY67S93A==',
    'V+KgSWsw/Tql6NGliPGpgxbVovPEqbmTu/PH+5djMAgD1RXWVzbgtdM8cBl/VbYH5MGCv25M94tCSlVQCc4NLg==',
    '99inm+u+avtRkLecdUPEKD02WkmEAtTPBHWfp2MOUoIUGC0sJXSpfWXCC/vrIaj0StMyzobqdykOX2xhdAth+A==',
    '5IZIHL62kjT0bFHBh2rjM+ZMBkvhMM0hird5aDLwisQPJMWpdcn2bMXGj0SbxPxcJ5BRIcG3k+dEwRJY5s6Tdw==',
    'g55oLbWRGp42jwXXraQROD/4mbhdGWgIlgOAnJUKzAmdb5CJCdNnVdYHRzrF/D+VyhyvVoiuWQhMEI5ceNQF/w==',
    'is8it3azN7edtkc9Sh6FOnJ9m2XvMgXqEM6BOG9gxfNk55b0g/hW9uPCbDR7RtiIsIb3u75v8efm0Z01UAaolA==',
    'wjIgxqnl6HIxSfXxJq+ODcxKA8nfjU8cu38Z7GEvqAe6YiBIrrinfAHSMBOdy0F8jd70jjChNA+VBV+gVDM3uQ==',
    'c5I52C+GTgmQo3W3fdwN4fHFFjeAtMKdY8AVwaGkdeQSactoyEBjYFBWIzGmFyx9f0R+IZdxFwki0B20WTrlkw==',
    'im63KuwPSLN/wAoYdk2jIRvqxNO3LDoR4FmASsQOzySqyMpPgBmImB7A918t4HfpWwsa1r3aob8wYX6c4nQsWA==',
    'R7pA8XgkQjFC06nYKXM3Qp+z1+eBAR6VmwfbLcSnuA76qE70cDx9L736Xgont0VdQzERpNTsLfd/6U2GHOzrMw==',
    'kPPmtBG29QWawz/nISoZ839dISTTR7ch8Gh+Q4iqqK5o1Zj/6r7zNx88m+e5QwkUKZvJGScTs9Nl1b9/bzc8LA==',
    'H1u3Zuv+jsFAUABDvjf28lcWOefV3AjYJ03z9soRmjZlHByowwN8+hJEcz+Uyl5owW7CUmoigOvn38m5jG9EXg==',
    'ph2rddwdk5BgJNP+oKWZwvVX7ouQ0RDl3UOICE550yzulOnwN9Yq31Xfprk75vmgu8tU9xNghaYQ3CcimoBUkw==',
    'jkEGJxPvr6H3SHARXt7BtagCEdtJDxqNVpEGIdDcfvLLdti1FFPK5X3clS2noFfgfj4qvprV5p7qnvouQVR5Mg==',
    'pKA9m6Xi3/cc2tgaro2uDK0FZTBjMhzA3/1P5QAPlMuOdZd4ZZl+po8oB6J+SxEy5tI/iFOcXzcriZsw5qR1Iw==',
    '0rRmGqZYYrSBkR4QMT0SOzFoIfBWqKbvuuTegnNzeES87aS7SQNRumUFsMCXoFPeBd5DauV8CKGDeXKJValY0A==',
    'koXvRLSwPjfCO8X+ITN5IPMViAF7eJm1TQh09nH8gYxNgAgF+tm4sDzioCZzlRRjafylUz8ZmxylcNLQ7gm+Lw==',
    'XOBy55GiTvEJroyQgCSbA2wtfHrhWlndezBQXjEas1iEKGejKV27OhTHOEkds99QHg92tb2/uAtz6hjKBbISmA==',
    '8hsmz6Hn8XIqhvB5YTRi7OdABV6zlrBuOBnXOhD+GCh9u4rIUQSjSMte1i4auvw5wwxAlHVJ87Qj/m3AKTAo6Q==',
    'eowY/kPvChJ3/5hkOdiAF3cT++/Pg3MRckvynvQHrH//+BTwZwrzSqy4Ia0mJd9U8RBZCesSm0X0/lxkBDwajw==',
    '8BfV4xpw5FTugwdvtqpNVw5gPJpEhS4roH059ebKMKZZPQWnke/Vu6ePVNGP2BZ9ICA879zuZVdpKJquN3dSEA==',
    'xKrzP9i/WO0+SaEaW6vlFWXWxSdCH+LzjTzlUzjTVW+VGwHEKNJ0CFKbh6nqUAVDmUT+Vnvq0ftQpMMe17Hmxg==',
    'Myi7ojWlcQ4igkpUT4OztpFqvLPuq48aeKY7BXD3W11SJiOPmiOlqw8Qh2aP9pgT+Q2YTedsPUYdXkBKvZ1L5g==',
    'EQf2KPmJiW0NZzj1XfXV6e72Ce+ur3ar75lAoP3V2lB3FA+JIpPnvERkEWbuXtoOh/d+5dG0yszROVwd+SErAg==',
    'FPkRtpLmKAZtSI5EIOLKy88IuIgjdf+8cn3Q34OjpTyLUqpCGMSuB05oxBgJj0F9oM4XQUBfg8qUjQOGlqwTqA==',
    '4+YiQw8XQ/w3e6VOhf0wys9/jlKeg3zl4aRXv9GEx30uNJ6ftYUgXNP7rst7ztFTqBTXMJf8SoBkgixaI/BjYQ==',
    'fW30nOi3B97OYOS2qyRy+3bUX/F4+OibkPuUTFmx9HGn1KbDq0tEzKZfkbNys0ndJHVoSfhhE11Ba2t5/psQag==',
    'yMVLvIs+Yhjg5tgkfAvM8Zbd26/IvsqKdQrfQGG1KjW4QM3OEzAQHGy3TKrd0jCY9L4Csyx8em2rDuSfPwbLSA==',
    'k/66gcHbvU/n3cdvRpLDS5FzYFjCFnxKFSxoUoZEJ7vzKElvuYChNM05zsobUSAHRdgM7Y8N0n6dLf6JUXFLpQ==',
    'EIiLRNM0RgUekAHb/Lb3nMkg8ak4rzalDoHYLPU+iWQdx2xX08Eopg5p/lG5fdKpwJbdVKJVNUemvBeX/crxQQ==',
    'lZFKjU3NyLqvvxKQW30cKdoBlzoo/LxLgxYtHPVL6uGxfAGGHVafIFhTbA2vZlHG5JFLN5ulIAi4BRxjjP4tgw==',
    'MqRyvPZ0f/RjaeRFpMwK104wz204v1gIqC7iiktiPWo+kfHcfvWz1P61EmbRN4MRwR7XRbd6aFNsALLYn8IJ7g==',
    'ToezGpzbrMSh1v0xEUT3cqR2jaKG0sbuvNdSjat4bSW30Jlc9e9wxRz0u4L8sMCIWtr82KoKrziRGpMLgXqbjw==',
    '02JXw5iOlf7HH1XxPpe8+nbYTanOw+/WD7j9btt/I12Rt0qT5fbtXbUbnRIgHNJzGwc4BEbLRY78jnlTQnCtbw==',
    'RxyOegmU0IjiIhyuSSSoALjLXuYpKjqkp+eLDUVGY5zBLKOdVR+pYdT8G/H7ewoSSHDw7zB5r/XD8d2W39mBdQ==',
    'B3PZ6XlauqoRRJwQ2WfhEBSDKxROXxbAKJdOi2F/pQ1RdodwXdCOXL/AS4AetTGDCOtZrstaJirt3mGqtHHr0Q==',
    'AAX57Q3MVLao10GnIKholbTLm7yhDoj+3BE480nmwUAvMhkM7htLfbcDFjxrYAJCZH/sPQb7jSrD+G7xqJx6mQ==',
    '2/tXn256ufWtL1DXqUPwAQcmHUEdHLkEsnNuAF/eXqdw3TA6/1QU+w9LBLGv2glTNDOIt7L74YqaHx85XzSk4Q==',
    'HxMsWk3Z4fAlqa1YIqSc1yZgd3KWrdZ0VryPRS2LHEe0BK9XJF/mlCfmbwrxGFxk7fBKMnbqDeV352+sw6BQTg==',
    'ghp4QOd8+LLKcEuaFrJVxeMUG3eZtwGmWOFOdGv15LDsJvL59487dGlxYEmgirv+6ba+jXx+pMiJp2/AeSMiBA==',
    'oN1UKZFTsOXF+GE+fICKnhNRYZ5XZW4RW2lmJe/uBYwzXNJdDgppQ4qWxoMoAFP0qpnNOmOFAKt6tPod0ZwyOQ==',
    'dYFtfUX+Y7LUGoRhF5DfRS8bb24W0x3S1cYaI2G7e0AfRLJDFuEn7IRToRD3cqMRarn7cmw2ZBBK+AK5A0RDfw==',
    'c75FmGc41u/KW+yj57RYvtA7jsOYuqRm2Wa16J79YoTKs8+YCPwSOAi8hVqiBuUiu+n6QbIOlr9dNpH1aklIwA==',
    'mJDz5jVuo7vf3Urb4s6meu/eRjZvPYOcPSVn6CXQkv5I/9mLOmVO+CqVqMOOIYTiZ7wejB8+B+VNSvVgbYF9OQ==',
    'WKLqrhbFA73Oh/VYe4rrS4j4GvxFMiEuBNZXq3zbBvz6M3dS2CSIqB5NoElbVNCwzQrEqLqJlKGHe5Zi1VsdDA==',
    'pI9XgyGNyI0eBq0Gty0500e+25fHjcU28kOs1GO2QXfS8WsEqfdgG/WoHZEJ0PLPlQ0phCVnbLA/Yc3aLL0OrQ==',
    'Nt5//0kjCC754DzUyytdOFltUtVLi+mORSHRgOiVzbOmfErYCZiRqQedGd94ld/zj+e+xD/g2aOn2dzLKQm+JQ==',
    'DWC69GFO2DbOj7o+jb9mmif8UkpHqtJE8r8L0GlR4NYfwV8/UkmgB5Hx1uNfve725HjkOdXT4nMhfxCYQSa8sQ==',
    'FZtktPMA4OOR61u5wH6dQV58HG8R8Zyc8yJS/nuqsg/aHOFieciLtc+zQkS5cGhHATNMmPKcvBri9z3/q1cXTg==',
    'L91OtzJGd54934NV0PQC8v/OS7SiCW8J6HkMlxVtNqyLtp35XmPmjZMc7L7AcfBGO26hMcp4yqv9kmNMAI8udg==',
    'XLiwh2p5wxTLrb+SMQrZn+UQc4erj0kKBR5o84er6IgGz56+MJsPJyaesUSUxkqAtdre8GwOx89CCVvDNaEuog==',
    'paVo66UnV5g8XPCeNyj1GpFR2gXbapEoCFpeMFnjcX0hOe/vCVX6U4nNd5nMM9i+Xlt0jZ+koD4y4Pv29IBcbQ==',
    'zYOqef94RC2oi2kLVOXsZfjoI2qIhe2az9VIfO0Z+K2sDi6WsoN50KJ5jjpAZFbpXH8gS7iBbgqnP6DtSwuXoQ==',
    'JS2WLaXpfamr6j3Vqf/db0lu9twUVWt3BeRVyW9lup2XJ5GT14QrN+1944/9y+Gw5NKsR78xW8urHYk5yPJrgQ==',
    'cY+4c6W+qplz2VwYUsjXvyHgfI35YIRGI58lN1IWmeukyLaQFPyFEvyoTQRGNN4mja//i5A6yjM2nWHpG1tliw==',
    'X1hAzEPdjMES3Zm9C35jnBU4VGwSOXfneoI0dtzxra46jqJRIkYKYt8kDZP3LFW3l69N4Ih8VUzGNlbyk1cyYg==',
    '2yA1bPCdp5wob0/eHqGf0qfu2FCqQuD6QTcglv2+cRfGi7j7e4vIjG6hRc1HLjXYJmDUx9zOLh0sRS7oGuO34A==',
    'LtFP/zENgTQElag3xt1s6Q/+I7WoHAGWIGAD8nw5k0qAqTUdmy7ebLSJqt4b7sno/92guCh8aplYM/ypHM5WAA==',
    'vvFJFQYjZx+kiaHMw0pFmGYDNXmiknS/MdzgHMSFXW8SKi6m5DSTeRs6ZpQfbT/+Uwguq8DTaI3qBdS8dYL4hw==',
    'qtGG38Z1ik1aTOQpoWctgxksRZgerDwHpQBi8clJ/J8Ry+ZbbZ6v42pR7GsVcYHM0SGsLAJnzAEQNrkf86g6dg==',
    '3lgiljGNorq1QrwaNSW2HvGdWTFuKBsEEzuwEqfBS18sf9ODAmD2sBXKLWYkclHC2Gu3ZGqs0I/KJr9pD+fOMQ==',
    'XL9FZenV/UK9Ex/Ju0EVz44QtmUdQHWZJI61szDDs+X6/G4WLKf03zlbqlmryuf5e3olUa17cCuRos4jCdIguA==',
    'Ra+ETgnHbWFwzaA/7HlQlwsyuDZOn40oAq6xG1oRSaylqlG4yJsoKpCBndA8V73HK0WbkjWE+l+IoBn6EZxs1g==',
    'gd8vi8Ds5+kA7Qqba9FldBpN9GBRXiSL/ncsilerGUckw2AcJ93gq7bX+q5BzEvQDmyKfUrrl5BQwCL8znTZ5g==',
    'YMzGQaTD1HZlsYGLLYTuFUZog8FUHEj/lv6LErG1DTJjEPfpl/4KUHRtuS4MNPw8OIk8vEle3AxV7Zuikia3/Q==',
    '0iEiZaFqR0rT/3JaCQ+ZM8Q0jAPhs6H9XYZtj9Ve83i6Wy41xV4QYrAmsP2JVYc5RCsyUrict+NufxaNenk29g==',
    'ypv5uaauOx+42AGydol5m0FjjlbGU99C0gb+godcX4zHM24VCnA8bYIByaBR6nhSaZN5/I/mLhVqLVqVsVQIqw==',
    'Rn0KZtOFnZmlkqIG07jS2awkNy1S3KhcWPrQQZADpdqcr0a6SyRWnCWrTc+FFZJqHPd70HUe/HGqDI4zNyAJUw==',
    'I47PCho/Ya/EKHc9fztLxoHP8ZW6sWTmsNgND+8rzkb5FYSWxjMy4Q8HI8v374f9x4JIVVvnQGSzQxJkrEIsSg==',
    'mcew6417lxE7m/2ML2Vsm+uXhhXNE566Y1QFG3XfGEQTr7kb5iLflj8/0LarPMIG1dWNam7FZ42gP+FxTVWZkQ==',
    'RDgudXPws/F2si+YGTe8QMcGWOXimH0cKfg5odDqi3RQPJojJOC8NShEFemaResyD6SU6xUvHdv8dOAL3mpB3A==',
    'x5BRQ2BSpGyWLPpDav3sSjaZIwtFN5AvXtKByoesEya73U3esTOnNUllJ4u+cr8urErcdIzp9XrqfrbKp+a7kA==',
    '2nOgleG3aUYbKtFWaSMyJc7JDLzkzScs0PPG42jXm1/eO/rYJyrEHmIf0RgYMM3cYU0N781EsoPuc99h+eZEpA==',
    'M3Ds8wpWc6izI3QKMGsT3uc+J3yU4sPpMwbZ2cEGNAZL3P9V79deuHB6NrA3PqFABiaqg3CNdX9AAlyESCR4dw==',
    'cQJOvfzfIR0xD+o6JTu3nAxTmp1FzkxeOJFLZGNrXO9ehZiY/7BuaksHeT8DL1h1DHfxC6Oa1GX1mJTrnUlL2A==',
    'Kvfe1av0IUvzG8unUvCk19Y8ajNYw6aMRig3E9FYibrAZBi2HZVl5kmzYYGKhspwXkGn9cdd5KL25/4PP21Qeg==',
    'l4P9Er4iPDsISiOoyK6BRlC7cuiZfopDjLhp0Dd1gyc0oltGAYG/GeSHEjBjT/Er/8/yuH9fYb8fBo5ZPpQJZw==',
    'iFBtvoHZ90Z0JE8O55NTazqwa9Munre8ybNUX/efifZXPNkBNq4M0w8odEPiiZvrJ9x+fGf6szWfMcttHu3knQ==',
    '5boe2xRxM6uOndXAEt9UC0cbIko8BaeWfzY/Mz01s0Q+f2jJ7lIt4PovlMTu0We+ltZ3RcR/zGNMXi8juk01fQ==',
    'Vv6rKNcr29uH0y8IrQiiQS+1L7M0OLaOFBu1Ra3iRpn15p/DRdhfhGN6wwVGhxGWe0R6DczfJteOYBFJlm1h8g==',
    'rKpO+/K4ddRtfDtr52bVvSob8V5nBZlRiVepd9vvbJZcYAuwMjnZ2/0152/IhVSlgoDDai9rvSMtLDXUYFJoeQ==',
    'TXs+OqH0yNEth4qVPeG6Po+e+I0bG5yF7UOILtzJkTrdDzzsopV0NgcJ+DG+IAhDsnQh4uqjtIKhPIVN8tEVNQ==',
  ],
}


// SM3 hash (GB/T 32918.4). Pure JS, 32-bit ops, no BigInt.

function rotl(x, n) { return ((x << n) | (x >>> (32 - n))) >>> 0 }

function sm3Bytes(input) {
  const len = input.length
  const bitLen = len * 8
  const padded = []
  for (let i = 0; i < len; i++) padded.push(input[i] & 0xff)
  padded.push(0x80)
  const blocks = Math.ceil((padded.length + 8) / 64)
  const total = blocks * 64
  while (padded.length < total - 8) padded.push(0)
  // 64-bit big-endian bit length (JS numbers cover up to 2^53 bits)
  const hi = Math.floor(bitLen / 0x100000000)
  const lo = bitLen >>> 0
  padded.push((hi >>> 24) & 0xff, (hi >>> 16) & 0xff, (hi >>> 8) & 0xff, hi & 0xff)
  padded.push((lo >>> 24) & 0xff, (lo >>> 16) & 0xff, (lo >>> 8) & 0xff, lo & 0xff)

  let v0 = 0x7380166f, v1 = 0x4914b2b9, v2 = 0x172442d7, v3 = 0xda8a0600,
      v4 = 0xa96f30bc, v5 = 0x163138aa, v6 = 0xe38dee4d, v7 = 0xb0fb0e4e

  const w = new Array(68)
  const w1 = new Array(64)

  for (let off = 0; off < total; off += 64) {
    for (let j = 0; j < 16; j++) {
      const i = off + j * 4
      w[j] = ((padded[i] << 24) | (padded[i + 1] << 16) | (padded[i + 2] << 8) | padded[i + 3]) >>> 0
    }
    for (let j = 16; j < 68; j++) {
      const x = w[j - 16] ^ w[j - 9] ^ rotl(w[j - 3], 15)
      w[j] = (x ^ rotl(x, 15) ^ rotl(x, 23) ^ rotl(w[j - 13], 7) ^ w[j - 6]) >>> 0
    }
    for (let j = 0; j < 64; j++) w1[j] = (w[j] ^ w[j + 4]) >>> 0

    let a = v0, b = v1, c = v2, d = v3, e = v4, f = v5, g = v6, h = v7
    for (let j = 0; j < 64; j++) {
      const tj = j < 16 ? 0x79cc4519 : 0x7a879d8a
      const a12 = rotl(a, 12)
      const ss1 = (rotl((a12 + e + rotl(tj, j % 32)) >>> 0, 7)) >>> 0
      const ss2 = (ss1 ^ a12) >>> 0
      let ff, gg
      if (j < 16) {
        ff = (a ^ b ^ c) >>> 0
        gg = (e ^ f ^ g) >>> 0
      } else {
        ff = ((a & b) | (a & c) | (b & c)) >>> 0
        gg = ((e & f) | (~e & g)) >>> 0
      }
      const tt1 = (ff + d + ss2 + w1[j]) >>> 0
      const tt2 = (gg + h + ss1 + w[j]) >>> 0
      d = c
      c = rotl(b, 9)
      b = a
      a = (tt1) >>> 0
      h = g
      g = rotl(f, 19)
      f = e
      e = (tt2 ^ rotl(tt2, 9) ^ rotl(tt2, 17)) >>> 0 // P0(TT2)
    }
    v0 = (v0 ^ a) >>> 0; v1 = (v1 ^ b) >>> 0; v2 = (v2 ^ c) >>> 0; v3 = (v3 ^ d) >>> 0
    v4 = (v4 ^ e) >>> 0; v5 = (v5 ^ f) >>> 0; v6 = (v6 ^ g) >>> 0; v7 = (v7 ^ h) >>> 0
  }

  const out = new Array(32)
  const regs = [v0, v1, v2, v3, v4, v5, v6, v7]
  for (let j = 0; j < 8; j++) {
    out[j * 4] = (regs[j] >>> 24) & 0xff
    out[j * 4 + 1] = (regs[j] >>> 16) & 0xff
    out[j * 4 + 2] = (regs[j] >>> 8) & 0xff
    out[j * 4 + 3] = regs[j] & 0xff
  }
  return out
}

function bytesToHex(bytes) {
  let s = ''
  for (let i = 0; i < bytes.length; i++) s += ('0' + bytes[i].toString(16)).slice(-2)
  return s
}

function hexToBytes(hex) {
  const out = new Array(hex.length / 2)
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16)
  return out
}

function sm3Hex(inputBytes) { return bytesToHex(sm3Bytes(inputBytes)) }



// 256-bit modular arithmetic, 16-bit limbs, no BigInt in the hot paths.
// Plain ctx: add/sub/inv (generic odd modulus).
// Mont ctx: CIOS Montgomery multiplication for fast field arithmetic.

const LIMBS = 16

function hexToLimbs(hex) {
  const out = new Array(LIMBS)
  for (let i = 0; i < LIMBS; i++) {
    const end = hex.length - i * 4
    out[i] = parseInt(hex.substring(end - 4, end), 16)
  }
  return out
}

function limbsToHex(a) {
  let s = ''
  for (let i = LIMBS - 1; i >= 0; i--) s += ('000' + a[i].toString(16)).slice(-4)
  return s
}

function clear(array) { for (let i = 0; i < array.length; i++) array[i] = 0; return array }
function zeros() { return clear(new Array(LIMBS)) }

function cmp(a, b) {
  for (let i = LIMBS - 1; i >= 0; i--) {
    if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1
  }
  return 0
}

function subInto(r, a, b) {
  let borrow = 0
  for (let i = 0; i < LIMBS; i++) {
    let d = a[i] - b[i] - borrow
    if (d < 0) { d += 0x10000; borrow = 1 } else { borrow = 0 }
    r[i] = d
  }
  return borrow
}

function addInto(r, a, b) {
  let carry = 0
  for (let i = 0; i < LIMBS; i++) {
    let s = a[i] + b[i] + carry
    if (s >= 0x10000) { s -= 0x10000; carry = 1 } else { carry = 0 }
    r[i] = s
  }
  return carry
}

function isZero(a) { for (let i = 0; i < LIMBS; i++) if (a[i] !== 0) return false; return true }
function isOne(a) {
  if (a[0] !== 1) return false
  for (let i = 1; i < LIMBS; i++) if (a[i] !== 0) return false
  return true
}
function isEven(a) { return (a[0] & 1) === 0 }
// Generic modulus context (modulus M odd, < 2^256).
function ModCtx(modHex) {
  const M = hexToLimbs(modHex)

  function add(a, b) {
    const r = zeros()
    const carry = addInto(r, a, b)
    if (carry || cmp(r, M) >= 0) subInto(r, r, M)
    return r
  }
  function double(a) { return add(a, a) }
  function triple(a) { return add(a, double(a)) }
  function sub(a, b) {
    const r = zeros()
    const borrow = subInto(r, a, b)
    if (borrow) addInto(r, r, M)
    return r
  }
  // Binary extended Euclid inverse mod odd M.
  // 原地二进制扩展欧几里得：每实例一套固定缓冲，每次求逆零分配。
  const iu = zeros()
  const iv = zeros()
  const ix1 = zeros()
  const ix2 = zeros()
  function shiftRight1Into(r, a) {
    for (let i = 0; i < LIMBS; i++) {
      const next = i + 1 < LIMBS ? a[i + 1] : 0
      r[i] = (a[i] >> 1) | ((next & 1) ? 0x8000 : 0)
    }
  }
  function halveSumInto(r, a, b) {
    const carry = addInto(r, a, b)
    let high = carry
    for (let i = LIMBS - 1; i >= 0; i--) {
      const cur = r[i]
      r[i] = (cur >> 1) | (high ? 0x8000 : 0)
      high = cur & 1
    }
  }
  function inv(a) {
    for (let i = 0; i < LIMBS; i++) {
      iu[i] = a[i]
      iv[i] = M[i]
    }
    clear(ix1)
    ix1[0] = 1
    clear(ix2)
    while (!isOne(iu) && !isOne(iv)) {
      if (isEven(iu)) {
        shiftRight1Into(iu, iu)
        if (isEven(ix1)) shiftRight1Into(ix1, ix1)
        else halveSumInto(ix1, ix1, M)
      } else if (isEven(iv)) {
        shiftRight1Into(iv, iv)
        if (isEven(ix2)) shiftRight1Into(ix2, ix2)
        else halveSumInto(ix2, ix2, M)
      } else if (cmp(iu, iv) >= 0) {
        subInto(iu, iu, iv)
        const borrow = subInto(ix1, ix1, ix2)
        if (borrow) addInto(ix1, ix1, M)
      } else {
        subInto(iv, iv, iu)
        const borrow = subInto(ix2, ix2, ix1)
        if (borrow) addInto(ix2, ix2, M)
      }
    }
    const out = new Array(LIMBS)
    const src = isOne(iu) ? ix1 : ix2
    for (let i = 0; i < LIMBS; i++) out[i] = src[i]
    return out
  }
  return { M, add, double, triple, sub, inv }
}

// Montgomery CIOS context for modulus M.
// R = 2^256. Values "in Montgomery form" are a*R mod M.
// montMul(x, y) = x*y*R^-1 mod M.
function MontCtx(modHex, RmodHex, R2Hex, n0inv) {
  const M = hexToLimbs(modHex)
  const ONE = hexToLimbs(RmodHex) // R mod M
  const R2 = hexToLimbs(R2Hex) // R^2 mod M
  const plain = ModCtx(modHex)

  // CIOS with the 16x16 inner loops unrolled 4x (20% faster on QuickJS).
  // 写入调用方缓冲的版本：点运算热路径用它，零分配。
  const t = new Array(18)
function montMulInto(r, a, b) {
  t[0]=t[1]=t[2]=t[3]=t[4]=t[5]=t[6]=t[7]=t[8]=t[9]=t[10]=t[11]=t[12]=t[13]=t[14]=t[15]=0; t[16]=0; t[17]=0
  for (let i = 0; i < 16; i++) {
    let C = 0
    const bi = b[i]
    { const v = t[0] + a[0] * bi + C; t[0] = v & 0xffff; C = v >>> 16 }
    { const v = t[1] + a[1] * bi + C; t[1] = v & 0xffff; C = v >>> 16 }
    { const v = t[2] + a[2] * bi + C; t[2] = v & 0xffff; C = v >>> 16 }
    { const v = t[3] + a[3] * bi + C; t[3] = v & 0xffff; C = v >>> 16 }
    { const v = t[4] + a[4] * bi + C; t[4] = v & 0xffff; C = v >>> 16 }
    { const v = t[5] + a[5] * bi + C; t[5] = v & 0xffff; C = v >>> 16 }
    { const v = t[6] + a[6] * bi + C; t[6] = v & 0xffff; C = v >>> 16 }
    { const v = t[7] + a[7] * bi + C; t[7] = v & 0xffff; C = v >>> 16 }
    { const v = t[8] + a[8] * bi + C; t[8] = v & 0xffff; C = v >>> 16 }
    { const v = t[9] + a[9] * bi + C; t[9] = v & 0xffff; C = v >>> 16 }
    { const v = t[10] + a[10] * bi + C; t[10] = v & 0xffff; C = v >>> 16 }
    { const v = t[11] + a[11] * bi + C; t[11] = v & 0xffff; C = v >>> 16 }
    { const v = t[12] + a[12] * bi + C; t[12] = v & 0xffff; C = v >>> 16 }
    { const v = t[13] + a[13] * bi + C; t[13] = v & 0xffff; C = v >>> 16 }
    { const v = t[14] + a[14] * bi + C; t[14] = v & 0xffff; C = v >>> 16 }
    { const v = t[15] + a[15] * bi + C; t[15] = v & 0xffff; C = v >>> 16 }
    { const v = t[16] + C; t[16] = v & 0xffff; t[17] = v >>> 16 }
    const m = (t[0] * n0inv) & 0xffff
    { const v = t[0] + M[0] * m; C = v >>> 16 }
    { const v = t[1] + M[1] * m + C; t[0] = v & 0xffff; C = v >>> 16 }
    { const v = t[2] + M[2] * m + C; t[1] = v & 0xffff; C = v >>> 16 }
    { const v = t[3] + M[3] * m + C; t[2] = v & 0xffff; C = v >>> 16 }
    { const v = t[4] + M[4] * m + C; t[3] = v & 0xffff; C = v >>> 16 }
    { const v = t[5] + M[5] * m + C; t[4] = v & 0xffff; C = v >>> 16 }
    { const v = t[6] + M[6] * m + C; t[5] = v & 0xffff; C = v >>> 16 }
    { const v = t[7] + M[7] * m + C; t[6] = v & 0xffff; C = v >>> 16 }
    { const v = t[8] + M[8] * m + C; t[7] = v & 0xffff; C = v >>> 16 }
    { const v = t[9] + M[9] * m + C; t[8] = v & 0xffff; C = v >>> 16 }
    { const v = t[10] + M[10] * m + C; t[9] = v & 0xffff; C = v >>> 16 }
    { const v = t[11] + M[11] * m + C; t[10] = v & 0xffff; C = v >>> 16 }
    { const v = t[12] + M[12] * m + C; t[11] = v & 0xffff; C = v >>> 16 }
    { const v = t[13] + M[13] * m + C; t[12] = v & 0xffff; C = v >>> 16 }
    { const v = t[14] + M[14] * m + C; t[13] = v & 0xffff; C = v >>> 16 }
    { const v = t[15] + M[15] * m + C; t[14] = v & 0xffff; C = v >>> 16 }
    { const v = t[16] + C; t[15] = v & 0xffff; t[16] = t[17] + (v >>> 16); t[17] = 0 }
  }
  for (let j = 0; j < 16; j++) r[j] = t[j]
  if (t[16] !== 0 || cmp(r, M) >= 0) subInto(r, r, M)
}

function montMul(a, b) {
  const r = new Array(16)
  montMulInto(r, a, b)
  return r
}

  function toMont(a) { return montMul(a, R2) }
  const PLAIN_ONE = hexToLimbs('0000000000000000000000000000000000000000000000000000000000000001')
  function fromMont(a) { return montMul(a, PLAIN_ONE) }

  function add(a, b) { return plain.add(a, b) }
  function double(a) { return plain.double(a) }
  function sub(a, b) { return plain.sub(a, b) }
  function triple(a) { return plain.triple(a) }
  // inverse of Montgomery value a = x*R: returns x^-1 * R.
  function inv(a) { return toMont(plain.inv(fromMont(a))) }

  return { M, ONE, montMul, montMulInto, toMont, fromMont, add, double, sub, triple, inv, plain }
}



// Ordinary field residues in radix B = 2^16. The SM2 field prime satisfies
// B^16 = B^14 + B^6 - B^4 + 1 (mod p). The largest folded coefficient
// is below 2^40, within the exact integer range of a JS Number.
function primeField(pHex) {
  const plain = ModCtx(pHex)
  const t = new Array(31)
  function mulInto(out, a, b) {
    // Column k collects a[i] * b[k-i]. A column fits in 36 exact integer
    // bits. Cache the input limbs and write each scratch column once.
    // Squaring doubles each off-diagonal pair and adds the diagonal once.
    const a0 = a[0], a1 = a[1], a2 = a[2], a3 = a[3]
    const a4 = a[4], a5 = a[5], a6 = a[6], a7 = a[7]
    const a8 = a[8], a9 = a[9], a10 = a[10], a11 = a[11]
    const a12 = a[12], a13 = a[13], a14 = a[14], a15 = a[15]
    if (a === b) {
      t[0] = a0 * a0
      t[1] = 2 * (a0 * a1)
      t[2] = 2 * (a0 * a2) + a1 * a1
      t[3] = 2 * (a0 * a3 + a1 * a2)
      t[4] = 2 * (a0 * a4 + a1 * a3) + a2 * a2
      t[5] = 2 * (a0 * a5 + a1 * a4 + a2 * a3)
      t[6] = 2 * (a0 * a6 + a1 * a5 + a2 * a4) + a3 * a3
      t[7] = 2 * (a0 * a7 + a1 * a6 + a2 * a5 + a3 * a4)
      t[8] = 2 * (a0 * a8 + a1 * a7 + a2 * a6 + a3 * a5) + a4 * a4
      t[9] = 2 * (a0 * a9 + a1 * a8 + a2 * a7 + a3 * a6 + a4 * a5)
      t[10] = 2 * (a0 * a10 + a1 * a9 + a2 * a8 + a3 * a7 + a4 * a6) + a5 * a5
      t[11] = 2 * (a0 * a11 + a1 * a10 + a2 * a9 + a3 * a8 + a4 * a7 + a5 * a6)
      t[12] = 2 * (a0 * a12 + a1 * a11 + a2 * a10 + a3 * a9 + a4 * a8 + a5 * a7) + a6 * a6
      t[13] = 2 * (a0 * a13 + a1 * a12 + a2 * a11 + a3 * a10 + a4 * a9 + a5 * a8 + a6 * a7)
      t[14] = 2 * (a0 * a14 + a1 * a13 + a2 * a12 + a3 * a11 + a4 * a10 + a5 * a9 + a6 * a8) + a7 * a7
      t[15] = 2 * (a0 * a15 + a1 * a14 + a2 * a13 + a3 * a12 + a4 * a11 + a5 * a10 + a6 * a9 + a7 * a8)
      t[16] = 2 * (a1 * a15 + a2 * a14 + a3 * a13 + a4 * a12 + a5 * a11 + a6 * a10 + a7 * a9) + a8 * a8
      t[17] = 2 * (a2 * a15 + a3 * a14 + a4 * a13 + a5 * a12 + a6 * a11 + a7 * a10 + a8 * a9)
      t[18] = 2 * (a3 * a15 + a4 * a14 + a5 * a13 + a6 * a12 + a7 * a11 + a8 * a10) + a9 * a9
      t[19] = 2 * (a4 * a15 + a5 * a14 + a6 * a13 + a7 * a12 + a8 * a11 + a9 * a10)
      t[20] = 2 * (a5 * a15 + a6 * a14 + a7 * a13 + a8 * a12 + a9 * a11) + a10 * a10
      t[21] = 2 * (a6 * a15 + a7 * a14 + a8 * a13 + a9 * a12 + a10 * a11)
      t[22] = 2 * (a7 * a15 + a8 * a14 + a9 * a13 + a10 * a12) + a11 * a11
      t[23] = 2 * (a8 * a15 + a9 * a14 + a10 * a13 + a11 * a12)
      t[24] = 2 * (a9 * a15 + a10 * a14 + a11 * a13) + a12 * a12
      t[25] = 2 * (a10 * a15 + a11 * a14 + a12 * a13)
      t[26] = 2 * (a11 * a15 + a12 * a14) + a13 * a13
      t[27] = 2 * (a12 * a15 + a13 * a14)
      t[28] = 2 * (a13 * a15) + a14 * a14
      t[29] = 2 * (a14 * a15)
      t[30] = a15 * a15
    } else {
      const b0 = b[0], b1 = b[1], b2 = b[2], b3 = b[3]
      const b4 = b[4], b5 = b[5], b6 = b[6], b7 = b[7]
      const b8 = b[8], b9 = b[9], b10 = b[10], b11 = b[11]
      const b12 = b[12], b13 = b[13], b14 = b[14], b15 = b[15]
      t[0] = a0 * b0
      t[1] = a0 * b1 + a1 * b0
      t[2] = a0 * b2 + a1 * b1 + a2 * b0
      t[3] = a0 * b3 + a1 * b2 + a2 * b1 + a3 * b0
      t[4] = a0 * b4 + a1 * b3 + a2 * b2 + a3 * b1 + a4 * b0
      t[5] = a0 * b5 + a1 * b4 + a2 * b3 + a3 * b2 + a4 * b1 + a5 * b0
      t[6] = a0 * b6 + a1 * b5 + a2 * b4 + a3 * b3 + a4 * b2 + a5 * b1 + a6 * b0
      t[7] = a0 * b7 + a1 * b6 + a2 * b5 + a3 * b4 + a4 * b3 + a5 * b2 + a6 * b1 + a7 * b0
      t[8] = a0 * b8 + a1 * b7 + a2 * b6 + a3 * b5 + a4 * b4 + a5 * b3 + a6 * b2 + a7 * b1 + a8 * b0
      t[9] = a0 * b9 + a1 * b8 + a2 * b7 + a3 * b6 + a4 * b5 + a5 * b4 + a6 * b3 + a7 * b2 + a8 * b1
        + a9 * b0
      t[10] = a0 * b10 + a1 * b9 + a2 * b8 + a3 * b7 + a4 * b6 + a5 * b5 + a6 * b4 + a7 * b3 + a8 * b2
        + a9 * b1 + a10 * b0
      t[11] = a0 * b11 + a1 * b10 + a2 * b9 + a3 * b8 + a4 * b7 + a5 * b6 + a6 * b5 + a7 * b4 + a8 * b3
        + a9 * b2 + a10 * b1 + a11 * b0
      t[12] = a0 * b12 + a1 * b11 + a2 * b10 + a3 * b9 + a4 * b8 + a5 * b7 + a6 * b6 + a7 * b5 + a8 * b4
        + a9 * b3 + a10 * b2 + a11 * b1 + a12 * b0
      t[13] = a0 * b13 + a1 * b12 + a2 * b11 + a3 * b10 + a4 * b9 + a5 * b8 + a6 * b7 + a7 * b6
        + a8 * b5 + a9 * b4 + a10 * b3 + a11 * b2 + a12 * b1 + a13 * b0
      t[14] = a0 * b14 + a1 * b13 + a2 * b12 + a3 * b11 + a4 * b10 + a5 * b9 + a6 * b8 + a7 * b7
        + a8 * b6 + a9 * b5 + a10 * b4 + a11 * b3 + a12 * b2 + a13 * b1 + a14 * b0
      t[15] = a0 * b15 + a1 * b14 + a2 * b13 + a3 * b12 + a4 * b11 + a5 * b10 + a6 * b9 + a7 * b8
        + a8 * b7 + a9 * b6 + a10 * b5 + a11 * b4 + a12 * b3 + a13 * b2 + a14 * b1 + a15 * b0
      t[16] = a1 * b15 + a2 * b14 + a3 * b13 + a4 * b12 + a5 * b11 + a6 * b10 + a7 * b9 + a8 * b8
        + a9 * b7 + a10 * b6 + a11 * b5 + a12 * b4 + a13 * b3 + a14 * b2 + a15 * b1
      t[17] = a2 * b15 + a3 * b14 + a4 * b13 + a5 * b12 + a6 * b11 + a7 * b10 + a8 * b9 + a9 * b8
        + a10 * b7 + a11 * b6 + a12 * b5 + a13 * b4 + a14 * b3 + a15 * b2
      t[18] = a3 * b15 + a4 * b14 + a5 * b13 + a6 * b12 + a7 * b11 + a8 * b10 + a9 * b9 + a10 * b8
        + a11 * b7 + a12 * b6 + a13 * b5 + a14 * b4 + a15 * b3
      t[19] = a4 * b15 + a5 * b14 + a6 * b13 + a7 * b12 + a8 * b11 + a9 * b10 + a10 * b9 + a11 * b8
        + a12 * b7 + a13 * b6 + a14 * b5 + a15 * b4
      t[20] = a5 * b15 + a6 * b14 + a7 * b13 + a8 * b12 + a9 * b11 + a10 * b10 + a11 * b9 + a12 * b8
        + a13 * b7 + a14 * b6 + a15 * b5
      t[21] = a6 * b15 + a7 * b14 + a8 * b13 + a9 * b12 + a10 * b11 + a11 * b10 + a12 * b9 + a13 * b8
        + a14 * b7 + a15 * b6
      t[22] = a7 * b15 + a8 * b14 + a9 * b13 + a10 * b12 + a11 * b11 + a12 * b10 + a13 * b9 + a14 * b8
        + a15 * b7
      t[23] = a8 * b15 + a9 * b14 + a10 * b13 + a11 * b12 + a12 * b11 + a13 * b10 + a14 * b9 + a15 * b8
      t[24] = a9 * b15 + a10 * b14 + a11 * b13 + a12 * b12 + a13 * b11 + a14 * b10 + a15 * b9
      t[25] = a10 * b15 + a11 * b14 + a12 * b13 + a13 * b12 + a14 * b11 + a15 * b10
      t[26] = a11 * b15 + a12 * b14 + a13 * b13 + a14 * b12 + a15 * b11
      t[27] = a12 * b15 + a13 * b14 + a14 * b13 + a15 * b12
      t[28] = a13 * b15 + a14 * b14 + a15 * b13
      t[29] = a14 * b15 + a15 * b14
      t[30] = a15 * b15
    }
    for (let i = 30; i >= 16; i--) {
      const high = t[i]
      t[i - 2] += high; t[i - 10] += high
      t[i - 12] -= high; t[i - 16] += high
    }
    let carry = 0
    do {
      t[14] += carry; t[6] += carry; t[4] -= carry; t[0] += carry
      carry = 0
      for (let i = 0; i < 16; i++) {
        const value = t[i] + carry
        carry = Math.floor(value / 65536)
        t[i] = value - carry * 65536
      }
    } while (carry)
    for (let i = 0; i < 16; i++) out[i] = t[i]
    if (cmp(out, plain.M) >= 0) subInto(out, out, plain.M)
  }
  return {M: plain.M, mulInto: mulInto, inv: plain.inv}
}

function makeEc(field) {
  const mulInto = field.mulInto, MODP = field.M
  const ONE = zeros()
  ONE[0] = 1
  const S = []
  for (let i = 0; i < 22; i++) S.push(zeros())

  function zeroTo(r) { for (let i = 0; i < 16; i++) r[i] = 0; return r }
  function copyTo(r, a) { for (let i = 0; i < 16; i++) r[i] = a[i]; return r }
  function addTo(r, a, b) {
    const carry = addInto(r, a, b)
    if (carry || cmp(r, MODP) >= 0) subInto(r, r, MODP)
    return r
  }
  function subTo(r, a, b) {
    const borrow = subInto(r, a, b)
    if (borrow) addInto(r, r, MODP)
    return r
  }
  function dblTo(r, a) { return addTo(r, a, a) }
  function tripleTo(r, a) {
    dblTo(S[15], a)
    return addTo(r, S[15], a)
  }


  // dbl-2001-b (a = -3)：8 次模乘，比 dbl-2007-bl 少 1 次。out 不得与 P 别名。
  function dblInto(out, P) {
    const X = P.X, Y = P.Y, Z = P.Z
    if (isZero(Z)) {
      zeroTo(out.X); zeroTo(out.Y); zeroTo(out.Z)
      return
    }
    const delta = S[0], gamma = S[1], beta = S[2], alpha = S[3]
    const tmp = S[4], tmp2 = S[5]
    mulInto(delta, Z, Z)
    mulInto(gamma, Y, Y)
    mulInto(beta, X, gamma)
    subTo(tmp, X, delta)
    addTo(tmp2, X, delta)
    mulInto(tmp, tmp, tmp2)
    tripleTo(alpha, tmp) // alpha = 3*(X-delta)*(X+delta)
    mulInto(out.X, alpha, alpha)
    dblTo(tmp, beta)
    dblTo(tmp2, tmp)
    dblTo(tmp, tmp2) // 8*beta
    subTo(out.X, out.X, tmp) // X3
    addTo(tmp, Y, Z)
    mulInto(out.Z, tmp, tmp)
    subTo(out.Z, out.Z, gamma)
    subTo(out.Z, out.Z, delta) // Z3
    dblTo(tmp, beta)
    dblTo(tmp2, tmp) // 4*beta
    subTo(tmp2, tmp2, out.X)
    mulInto(out.Y, alpha, tmp2)
    mulInto(tmp, gamma, gamma)
    dblTo(tmp2, tmp)
    dblTo(tmp, tmp2)
    dblTo(tmp2, tmp) // 8*gamma^2
    subTo(out.Y, out.Y, tmp2) // Y3
  }

  // madd-2007-bl: Jacobian P + affine Q。out 不得与 P 别名。
  function maddInto(out, P, Q) {
    const X1 = P.X, Y1 = P.Y, Z1 = P.Z
    if (isZero(Z1)) {
      copyTo(out.X, Q.x)
      copyTo(out.Y, Q.y)
      copyTo(out.Z, ONE)
      return
    }
    const Z1Z1 = S[0], U2 = S[1], S2 = S[2], H = S[3], HH = S[4]
    const I = S[5], J = S[6], r = S[7], V = S[8], HpZ1 = S[9]
    const tmp = S[10], tmp2 = S[11]
    mulInto(Z1Z1, Z1, Z1)
    mulInto(U2, Q.x, Z1Z1)
    mulInto(tmp, Q.y, Z1)
    mulInto(S2, tmp, Z1Z1)
    subTo(H, U2, X1)
    if (isZero(H)) {
      addTo(tmp, S2, Y1)
      if (isZero(tmp)) {
        zeroTo(out.X); zeroTo(out.Y); zeroTo(out.Z)
        return
      }
      dblInto(out, P)
      return
    }
    mulInto(HH, H, H)
    dblTo(tmp, HH)
    dblTo(I, tmp) // I = 4HH
    mulInto(J, H, I)
    subTo(tmp, S2, Y1)
    dblTo(r, tmp) // r = 2*(S2-Y1)
    mulInto(V, X1, I)
    mulInto(tmp, r, r)
    dblTo(tmp2, V)
    subTo(tmp, tmp, J)
    subTo(tmp, tmp, tmp2) // X3 = r^2 - J - 2V
    addTo(HpZ1, Z1, H)
    mulInto(out.Z, HpZ1, HpZ1)
    subTo(out.Z, out.Z, Z1Z1)
    subTo(out.Z, out.Z, HH) // Z3
    subTo(tmp2, V, tmp)
    mulInto(out.Y, r, tmp2) // r*(V-X3)
    mulInto(tmp2, Y1, J)
    dblTo(tmp2, tmp2)
    subTo(out.Y, out.Y, tmp2) // Y3
    copyTo(out.X, tmp)
  }

  // For T = (k + 2^256 - 1)/2 mod n, the 256 signed bits
  // (2*bit(T,i)-1) sum to k when weighted by 2^i.
  function makeMulG(t, table) {
    let row = 15
    const acc = {X: S[16], Y: S[17], Z: S[18]}
    const next = {X: S[19], Y: S[20], Z: S[21]}
    const negative = {x: null, y: zeros()}
    function point(block) {
      let mask = 0
      for (let j = 0; j < 8; j++) mask |= ((t[block * 8 + j] >>> row) & 1) << j
      const positive = (mask & 128) !== 0
      const q = table(128 * block + (positive ? mask & 127 : 127 - mask))
      if (positive) return q
      negative.x = q.x
      subInto(negative.y, MODP, q.y)
      return negative
    }
    return {
      step() {
        const first = point(0)
        if (row === 15) {
          copyTo(next.X, first.x); copyTo(next.Y, first.y); copyTo(next.Z, ONE)
        } else {
          dblInto(next, acc)
          maddInto(acc, next, first)
        }
        if (row === 15) maddInto(acc, next, point(1))
        else {
          maddInto(next, acc, point(1))
          copyTo(acc.X, next.X); copyTo(acc.Y, next.Y); copyTo(acc.Z, next.Z)
        }
        return --row < 0
      },
      result() { return acc }
    }
  }

  function affineX(point) {
    if (isZero(point.Z)) return null
    const x = field.inv(point.Z)
    mulInto(x, x, x)
    mulInto(x, point.X, x)
    return x
  }
  return {makeMulG: makeMulG, affineX: affineX}
}

function makeSm2(consts) {
  const ctxN = ModCtx(consts.N)
  const montN = MontCtx(consts.N, consts.montN.Rmod, consts.montN.R2, consts.montN.n0inv)
  const ec = makeEc(primeField(consts.P))

  // scalar-arithmetic muls mod n via Montgomery (~12x faster than shift-add)
  function mulN(a, b) {
    return montN.fromMont(montN.montMul(montN.toMont(a), montN.toMont(b)))
  }

  // Decode only the public points selected by this signature.
  const decoded = []
  function table(index) {
    if (decoded[index]) return decoded[index]
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    const row = consts.combTable[index]
    const x = zeros(), y = zeros()
    let bits = 0, carry = 0, count = 0
    for (let i = 0; count < 64; i++) {
      carry = (carry << 6) | alphabet.indexOf(row.charAt(i))
      bits += 6
      if (bits < 8) continue
      bits -= 8
      const byte = (carry >>> bits) & 255
      carry &= (1 << bits) - 1
      const coord = count < 32 ? x : y
      const limb = 15 - ((count & 31) >>> 1)
      coord[limb] |= byte << ((count & 1) ? 0 : 8)
      count++
    }
    decoded[index] = {x: x, y: y}
    return decoded[index]
  }

  const N = hexToLimbs(consts.N)
  const maskModN = hexToLimbs('000000010000000000000000000000008dfc2094de39fad4ac440bf6c62abedc')
  function signedCombScalar(k) {
    const t = ctxN.add(k, maskModN)
    let high = (t[0] & 1) ? addInto(t, t, N) : 0
    for (let i = 15; i >= 0; i--) {
      const limb = t[i]
      t[i] = (high << 15) | (limb >>> 1)
      high = limb & 1
    }
    return t
  }
  const ONE_N = zeros(); ONE_N[0] = 1
  const defaultUserId = '1234567812345678'

  function strBytes(s) {
    // ASCII only (user IDs, device codes in this protocol)
    const out = new Array(s.length)
    for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 0xff
    return out
  }

  function zaBytes(pubXHex, pubYHex, userId) {
    const idBytes = strBytes(userId)
    const bitLen = idBytes.length * 8
    return sm3Bytes([(bitLen >> 8) & 0xff, bitLen & 0xff].concat(idBytes,
      hexToBytes(consts.A), hexToBytes(consts.B), hexToBytes(consts.GX),
      hexToBytes(consts.GY), hexToBytes(pubXHex), hexToBytes(pubYHex)))
  }

  function digestForSignature(pubXHex, pubYHex, message, userId) {
    const za = zaBytes(pubXHex, pubYHex, userId || defaultUserId)
    return sm3Bytes(za.concat(message))
  }

  function subN(v) {
    const t = zeros()
    subInto(t, v, N)
    return t
  }

  function reduceModN(bytes32) {
    let v = hexToLimbs(bytesToHex(bytes32))
    if (cmp(v, N) >= 0) v = subN(v) // one subtract: value < 2^256 < 2n
    return v
  }

  // Deterministic k: SM3(d || e || message || counter), reject outside [1, n-1].
  function deriveK(dBytes, eBytes, message, counter) {
    const h = sm3Bytes(dBytes.concat(eBytes, message, [counter & 0xff]))
    const k = hexToLimbs(bytesToHex(h))
    if (isZero(k) || cmp(k, N) >= 0) return null
    return k
  }

  // r = (e + x1) mod n; s = (k - r*d) * (1+d)^-1 mod n. sync, cheap.
  function finish(eLimbs, kLimbs, dLimbs, x1Limbs, dInv) {
    // x1 < p, may exceed n by at most one subtraction
    let x1 = x1Limbs
    if (cmp(x1, N) >= 0) x1 = subN(x1)
    const r = ctxN.add(eLimbs, x1)
    if (isZero(r)) return null
    const rd = mulN(r, dLimbs)
    if (isZero(ctxN.add(r, kLimbs))) return null // r + k == n
    const num = ctxN.sub(kLimbs, rd)
    const inv = dInv
    const s = mulN(num, inv)
    if (isZero(s)) return null
    return { r, s }
  }

  // (1+d)^-1 只与私钥有关：同一凭证的每次签名复用，省一次模逆。
  const invCache = {}
  function invFor(hexKey, dLimbs) {
    let v = invCache[hexKey]
    if (!v) {
      v = ctxN.inv(ctxN.add(dLimbs, ONE_N))
      invCache[hexKey] = v
    }
    return v
  }

  // Step machine: sign(message) with optional fixed k (tests).
  // drive: while (!job.step()) {} then job.result() -> uppercase 128-hex or null.
  function makeSignJob(opts) {
    const dLimbs = hexToLimbs(opts.privateKeyHex)
    const dInv = invFor(opts.privateKeyHex, dLimbs)
    const message = opts.message
    const userId = opts.userId || defaultUserId
    const eLimbs = reduceModN(digestForSignature(
      opts.publicKeyXHex, opts.publicKeyYHex, message, userId))
    const dBytes = hexToBytes(opts.privateKeyHex)
    const eBytes = hexToBytes(limbsToHex(eLimbs))
    let counter = 0
    let kLimbs = opts.kLimbs || null
    let inner = null
    let done = false
    let result = null

    function restart() {
      if (kLimbs === null) {
        let k = null
        while (k === null && counter < 256) {
          k = deriveK(dBytes, eBytes, message, counter)
          counter++
        }
        if (k === null) { done = true; return }
        kLimbs = k
      }
      inner = ec.makeMulG(signedCombScalar(kLimbs), table)
    }

    return {

      step() {
        if (done) return true
        if (inner === null) restart()
        if (done) return true
        const finished = inner.step()
        if (!finished) return false
        const pt = inner.result()
        const x = ec.affineX(pt)
        const sig = x === null ? null : finish(eLimbs, kLimbs, dLimbs, x, dInv)
        if (sig !== null) {
          result = (limbsToHex(sig.r) + limbsToHex(sig.s)).toUpperCase()
          done = true
        } else {
          // retry with fresh k (fixed-k mode must not retry)
          if (opts.kLimbs) { done = true; result = null } else { kLimbs = null; inner = null }
        }
        return done
      },
      result() { return result },
    }
  }

  return {makeSignJob: makeSignJob}
}

module.exports = { makeSigner: function() { return makeSm2(CONSTS) } }
