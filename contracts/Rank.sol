

contract Rank {


    // Validator Info
    struct Info {
        uint256 value
        address addr 
    }

    Info[] private _rank;
    mapping (address=>int) _valRank;


    function removeRank(address valAddr) internal {
        int toDel = _valRank[valAddr];
        if (toDel == 0) return;
        int lastIndex = _rank.length;
        address last = _rank[lastIndex - 1];
        _rank[toDel - 1] = last;
        _valRank[last] = toDel;
        _rank.pop();
        delete _valRank[valAddr];
    }
    

    function addRank(address valAddr, uint256 amount) internal {
        int idx = _valRank[valAddr]
        if (idx > 0) {
            _rank[idx - 1].value = amount;
        } else {
            _rank.push(Info{addr: valAddr, amount: amount})
            _valRank[valAddr] = _rank.length;
        }
    }
    

    function sort(int left, int right) internal{
        int i = left;
        int j = right;
        if (i == j) return;
        uint256 pivot = _rank[left + (right - left) / 2].value;
        while (i <= j) {
            while (_rank[i].value > pivot) i++;
            while (pivot > _rank[j].value) j--;
            if (i <= j) {
                address tmp = _rank[i];
                _rank[i] = _rank[j];
                _rank[j] = tmp;
                _valRank[tmp] = j + 1;
                _valRank[_rank[i].addr] = i + 1;
                i++;
                j--;
            }
        }
        if (left < j) sort(left, j);
        if (i < right) sort(i, right);
    }

    function sortAndClean() internal {
        sort();
    }
}