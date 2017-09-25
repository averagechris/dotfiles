let my_url = '';
let my_data = {};

function shit(url, data) {
    fetch(url, {
        method: 'POST',
        credentials: 'same-origin',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(data),
    })
        .then(response => {
            let reader = response.body.getReader();
            let decoder = new TextDecoder();

            reader.read().then(d => {
                if (d.done) {
                    return;
                }
        console.log(decoder.decode(d.value, {stream: true})); // eslint-disable-line
            });
        })
    .catch(response => console.log('there was an error:', response)); // eslint-disable-line
}

shit(my_url, my_data);
