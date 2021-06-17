const crypto = require('crypto')

function generateNonceForChallenge(challenge, complexity) {
  while (true) {
    const nonce = crypto.randomBytes(256).toString('hex')
    const hash = crypto
      .createHash('sha256')
      .update(challenge + nonce, 'hex')
      .digest('hex')

    const isValid = hash.startsWith('0'.repeat(complexity))

    if (isValid) {
      return nonce
    }
  }
}

console.log(generateNonceForChallenge(process.argv[2], process.argv[3]))
