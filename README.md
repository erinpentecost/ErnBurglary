# ErnBurglary
OpenMW mod that overhauls theft. No longer will NPCs forget that you were in their house when all their gems were stolen.

If an NPC greets you, they will remember that you were in the area (until you leave the area). If you steal things they own (even when they aren't watching you), you'll be caught once you leave the area.

Getting caught this way will first deplete the NPC's dispostion by the value of the stolen goods, and if there's any left over it will be added to your bounty.

Same for items owned by factions, but your faction reputation is affected instead. If you're a member of the faction and manage to get a bounty from the theft, you'll also be expelled.

If everyone that greeted you died before you left the area, then there won't be anyone to report the theft.

You'll be warned if you were spotted in the area when you enter sneak mode.

![a thief with a big bag, created with AI](title_image.jpg)

## Installing
Extract [main](https://github.com/erinpentecost/ErnBurglary/archive/refs/heads/main.zip) to your `mods/` folder.


In your `openmw.cfg` file, and add these lines in the correct spots:

```yaml
data="/wherevermymodsare/mods/ErnBurglary-main"
content=ErnBurglary.omwaddon
content=ErnBurglary.omwscripts
```

## Contributing

Feel free to submit a PR to the [repo](https://github.com/erinpentecost/ErnBurglary) provided you certify your contribution under the [Developer Certificate of Origin](https://developercertificate.org/).

### omwaddon
The omwaddon contains these entries:
* `fCrimeStealing` penalty set to 0.
* `ernburglary_spotted` spell that contains the penalty for being spotted.
