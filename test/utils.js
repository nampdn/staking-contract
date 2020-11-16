


exports.wait = function wait(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

exports.advanceTime =  function advanceTime(time) {
    return new Promise((resolve, reject) => {
        web3.currentProvider.send({
          jsonrpc: '2.0',
          method: 'evm_increaseTime',
          params: [time],
          id: new Date().getTime()
        }, (err, result) => {
          if (err) { return reject(err) }
          return resolve(result)
        })
    });
}

exports.assertRevert = async (promise, includeStr = "") => {
  return promise.then(() => {
      throw null;
  }).catch(e => {
      assert.isNotNull(e);
      if (includeStr != "" && e != null) {
          assert.include(e.message, includeStr);
      }
  });
}
