declare module "jsr:@supabase/supabase-js@2" {
  export function createClient(
    url: string,
    key: string,
    options: {
      global: { headers: Record<string, string> };
      auth: { persistSession: boolean; autoRefreshToken: boolean };
    },
  ): {
    auth: {
      getUser(): Promise<{
        data: { user: { id: string } | null };
        error: { message: string } | null;
      }>;
    };
    rpc(
      functionName: string,
      args: Record<string, string>,
    ): Promise<{ error: { message: string } | null }>;
  };
}
