"use client";

import { useState, useEffect, useCallback } from "react";
import { fetchPosition, PositionData } from "@/lib/lending";

export function usePosition(shieldedPositionId: string | null) {
  const [position, setPosition] = useState<PositionData | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  const loadPosition = useCallback(async () => {
    if (!shieldedPositionId) {
      setPosition(null);
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      const data = await fetchPosition(shieldedPositionId);
      setPosition(data);
    } catch (err: any) {
      setError(err?.message || "Failed to load position");
    } finally {
      setIsLoading(false);
    }
  }, [shieldedPositionId]);

  useEffect(() => {
    loadPosition();
  }, [loadPosition]);

  return {
    position,
    isLoading,
    error,
    refreshPosition: loadPosition,
  };
}
