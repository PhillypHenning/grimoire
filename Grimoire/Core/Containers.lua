local Grimoire = Grimoire

-- Shared inventory helpers. They live in core so that components like
-- Grimoire_Bags and Grimoire_Bank never depend on each other (ADR 0002).

Grimoire.MAX_PLAYER_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS

function Grimoire.IsPlayerBag(bag)
	return type(bag) == "number" and bag >= BACKPACK_CONTAINER and bag <= Grimoire.MAX_PLAYER_BAG
end

function Grimoire.GetBagIDs()
	local ids = {}
	for bag = BACKPACK_CONTAINER, Grimoire.MAX_PLAYER_BAG do
		ids[#ids + 1] = bag
	end
	return ids
end

-- Newer Mainline clients replaced bank bags with bank tabs; support either layout.
function Grimoire.GetBankIDs()
	local ids = {}
	local index = Enum.BagIndex
	if index and index.CharacterBankTab_1 then
		for i = 1, 6 do
			local id = index["CharacterBankTab_" .. i]
			if id then
				ids[#ids + 1] = id
			end
		end
	else
		ids[1] = BANK_CONTAINER
		for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + (NUM_BANKBAGSLOTS or 7) do
			ids[#ids + 1] = bag
		end
	end
	return ids
end

function Grimoire.ItemNameFromLink(link)
	return link and link:match("%[(.-)%]")
end

-- Returns an array indexed by slot: a compact item record, or false for an empty slot
-- (false rather than nil keeps the array contiguous for ipairs and SavedVariables).
function Grimoire.ReadContainer(bag)
	local items = {}
	for slot = 1, C_Container.GetContainerNumSlots(bag) do
		local info = C_Container.GetContainerItemInfo(bag, slot)
		items[slot] = info and {
			itemID = info.itemID,
			link = info.hyperlink,
			icon = info.iconFileID,
			count = info.stackCount,
			quality = info.quality,
		} or false
	end
	return items
end
